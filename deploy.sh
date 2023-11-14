gcloud services enable compute.googleapis.com artifactregistry.googleapis.com container.googleapis.com file.googleapis.com vpcaccess.googleapis.com redis.googleapis.com cloudscheduler.googleapis.com cloudfunctions.googleapis.com

export PROJECT_ID=speedy-victory-336109
export GKE_CLUSTER_NAME=sd-gke
export REGION=us-central1
export VPC_NETWORK=myvpc
export VPC_SUBNETWORK=myvpc
export FILESTORE_NAME=sdfilestore
export FILESTORE_ZONE=us-central1-b
export FILESHARE_NAME=sd
export BUILD_REGIST=sd-repo
export SD_WEBUI_IMAGE=${REGION}-docker.pkg.dev/${PROJECT_ID}/${BUILD_REGIST}/sd-webui:0.1
export NGINX_IMAGE=${REGION}-docker.pkg.dev/${PROJECT_ID}/${BUILD_REGIST}/sd-nginx:0.1
export AGONES_SIDECAR_IMAGE=${REGION}-docker.pkg.dev/${PROJECT_ID}/${BUILD_REGIST}/sd-agones-sidecar:0.1
export DOMAIN_NAME=sd.joey618.top


## GKE
gcloud container --project ${PROJECT_ID} clusters create ${GKE_CLUSTER_NAME} --region ${REGION} \
    --no-enable-basic-auth --release-channel "None" \
    --machine-type "e2-standard-2" \
    --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "100" \
    --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/cloud-platform" \
    --num-nodes "1" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias \
    --network "projects/${PROJECT_ID}/global/networks/${VPC_NETWORK}" \
    --subnetwork "projects/${PROJECT_ID}/regions/${REGION}/subnetworks/${VPC_SUBNETWORK}" \
    --no-enable-intra-node-visibility --default-max-pods-per-node "110" --no-enable-master-authorized-networks \
    --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver,GcpFilestoreCsiDriver \
    --autoscaling-profile optimize-utilization \
    --enable-image-streaming
gcloud container --project ${PROJECT_ID} node-pools create "gpu-pool" --cluster ${GKE_CLUSTER_NAME} --region ${REGION} --node-locations ${FILESTORE_ZONE} --machine-type "g2-standard-4" --accelerator "type=nvidia-l4,count=1" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "200" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/cloud-platform" --enable-autoscaling --total-min-nodes "1" --total-max-nodes "6" --location-policy "ANY" --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --max-pods-per-node "110" --num-nodes "1"


## Redis
gcloud redis instances create --project=${PROJECT_ID}  sd-agones-cache --tier=standard --size=1 --region=${REGION} --redis-version=redis_6_x --network=projects/${PROJECT_ID}/global/networks/${VPC_NETWORK} --connect-mode=DIRECT_PEERING
export REDIS_IP=$(gcloud redis instances describe sd-agones-cache --region ${REGION} --format=json 2>/dev/null | jq -r .host)


## Filestore
gcloud filestore instances create ${FILESTORE_NAME} --zone=${FILESTORE_ZONE} --tier=BASIC_HDD --file-share=name=${FILESHARE_NAME},capacity=1TB --network=name=${VPC_NETWORK}
export FILESTORE_IP=$(gcloud filestore instances describe ${FILESTORE_NAME} --project=${PROJECT_ID} --zone=${FILESTORE_ZONE} --format json |jq -r .networks[].ipAddresses[])


## Agones
helm repo add agones https://agones.dev/chart/stable
helm repo update
kubectl create namespace agones-system
cd agones
helm install sd-agones-release --namespace agones-system -f values.yaml agones/agones --version 1.30.0
gcloud compute --project=speedy-victory-336109 firewall-rules create agones-sd-firewall \
--network=${VPC_NETWORK} \
--action=ALLOW \
--rules=tcp:7000-8000,tcp:8080,tcp:8081,udp:7000-8000 \
--source-ranges=0.0.0.0/0 \
--project ${PROJECT_ID}


## Artifacts
gcloud artifacts repositories create ${BUILD_REGIST} --repository-format=docker --location=${REGION}
gcloud auth configure-docker ${REGION}-docker.pkg.dev


## build sd webui image
cd Stable-Diffusion-on-GCP/Stable-Diffusion-UI-Agones/sd-webui
docker build . -t $SD_WEBUI_IMAGE
docker push $SD_WEBUI_IMAGE
## Build nginx proxy image
cd ../nginx
sed "s@\"\${REDIS_HOST}\"@${REDIS_IP}@g" sd.lua > _tmp
mv _tmp sd.lua
docker build . -t $NGINX_IMAGE
docker push $NGINX_IMAGE
## Build agones-sidecar image
cd ../agones-sidecar
docker build . -t $AGONES_SIDECAR_IMAGE
docker push $AGONES_SIDECAR_IMAGE


## Deploy stable-diffusion
gcloud container clusters get-credentials ${GKE_CLUSTER_NAME} --region ${REGION}
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml
cd ..
envsubst < agones/nfs_pv_pvc.yaml  | kubectl apply -f -
envsubst < agones/fleet.yaml  | kubectl apply -f -
kubectl apply -f agones/fleet_autoscale.yaml
envsubst < nginx/deployment.yaml  | kubectl apply -f -


## Prepare Cloud Function Serverless VPC Access
gcloud compute networks vpc-access connectors create sd-agones-connector --network ${VPC_NETWORK} --region ${REGION} --range 192.168.240.16/28
## Deploy Cloud Function Cruiser Program
cd cloud-function
gcloud functions deploy redis_http --runtime python310 --trigger-http --allow-unauthenticated --region=${REGION} --vpc-connector=sd-agones-connector --egress-settings=private-ranges-only --set-env-vars=REDIS_HOST=${REDIS_IP}
##可能需要手动加一下alluser
export FUNCTION_URL=$(gcloud functions describe redis_http --region ${REGION} --format=json | jq -r .httpsTrigger.url)
gcloud scheduler jobs create http sd-agones-cruiser \
    --location=${REGION} \
    --schedule="*/5 * * * *" \
    --uri=${FUNCTION_URL}


## OAuth setup
Authorized redirect URIs: https://iap.googleapis.com/v1/oauth/clientIds/your_client_id:handleRedirect


## deploy IAP
gcloud compute addresses create sd-agones --global
gcloud compute addresses describe sd-agones --global --format=json | jq .address
kubectl create secret generic iap-secret --from-literal=client_id=aaa --from-literal=client_secret=bbb

envsubst < ingress-iap/managed-cert.yaml | kubectl apply -f -
kubectl apply -f ingress-iap/backendconfig.yaml
kubectl apply -f ingress-iap/service.yaml
kubectl apply -f ingress-iap/ingress.yaml

