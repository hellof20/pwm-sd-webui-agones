import json
import shutil
import requests
import time
import os
from pathlib import Path


sdk_http_port = os.environ['AGONES_SDK_HTTP_PORT']
mount_dir = '/sd_dir'

url = 'http://localhost:' + sdk_http_port + '/watch/gameserver'
time.sleep(30)
r = requests.get(url, stream=True)
if r.encoding is None:
    r.encoding = 'utf-8'

for line in r.iter_lines(decode_unicode=True):
    if line: 
        response = json.loads(line)
        if "user" in response['result']['object_meta']['labels']:
            userid = response['result']['object_meta']['labels']['user']
            print(userid)
            # setup folders here
            if os.path.isdir('/stable-diffusion-webui/outputs'):
                shutil.rmtree('/stable-diffusion-webui/outputs')
            Path(os.path.join(mount_dir, userid, 'outputs')).mkdir(parents=True, exist_ok=True)
            os.symlink(os.path.join(mount_dir, userid, 'outputs'), '/stable-diffusion-webui/outputs', target_is_directory = True)

            # if os.path.isdir('/stable-diffusion-webui/extensions'):
            #     shutil.rmtree('/stable-diffusion-webui/extensions')
            Path(os.path.join(mount_dir, userid, 'extensions')).mkdir(parents=True, exist_ok=True)
            os.symlink(os.path.join(mount_dir, userid, 'extensions'), '/stable-diffusion-webui/extensions/user_extensions', target_is_directory = True)

            break
