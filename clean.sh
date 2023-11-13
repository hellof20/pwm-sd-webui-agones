#!/bin/bash

export PROJECT_ID=speedy-victory-336109
export GKE_CLUSTER_NAME=sd-gke
export REGION=us-central1
export FILESTORE_NAME=sdfilestore
export FILESTORE_ZONE=us-central1-b
export BUILD_REGIST=sd-repo

echo "Deleting k8s resource ..."
gcloud container clusters delete ${GKE_CLUSTER_NAME} --project ${PROJECT_ID} --region ${REGION} --async --quiet > /dev/null

echo "Deleting Redis ..."
gcloud redis instances delete sd-agones-cache --region ${REGION} --project ${PROJECT_ID} --async --quiet > /dev/null

echo "Deleting Filestore ..."
gcloud filestore instances delete ${FILESTORE_NAME} --project=${PROJECT_ID}  --location=${FILESTORE_ZONE} --async --quiet > /dev/null

echo "Deleting ip address ..."
gcloud compute addresses delete sd-agones --global

echo "Deleting schedule job ..."
gcloud scheduler jobs delete sd-agones-cruiser --location=${REGION}

echo "Deleting cloud function ..."
gcloud functions delete redis_http --region=${REGION} 

echo "Deleting vpc-access connectors ..."
gcloud compute networks vpc-access connectors delete sd-agones-connector --region ${REGION} --async

echo "Deleting artifacts repositories"
gcloud artifacts repositories delete ${BUILD_REGIST} --location=${REGION} --async

echo "Completed, the resource is being deleted asynchronously."