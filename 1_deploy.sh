gcloud config set project $PROJECT_ID

# Deploy Cloud Function
cd src/sftp-function

# Grant user actAs permissions for service account
gcloud iam service-accounts add-iam-policy-binding projects/-/serviceAccounts/int-service@$PROJECT_ID.iam.gserviceaccount.com --member user:$(gcloud config list account --format "value(core.account)") --role roles/iam.serviceAccountUser

# Grant compute account storage object viewer permissions
PROJECTNUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PROJECTNUMBER-compute@developer.gserviceaccount.com" --role='roles/storage.objectViewer'
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PROJECTNUMBER-compute@developer.gserviceaccount.com" --role='roles/logging.logWriter'
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$PROJECTNUMBER-compute@developer.gserviceaccount.com" --role='roles/artifactregistry.writer'

# Deploy function
gcloud functions deploy sftp-zip-function \
  --gen2 \
  --runtime=nodejs20 \
  --region=$REGION \
  --source=. \
  --entry-point=sftp-zip-handler \
  --trigger-http \
  --no-allow-unauthenticated \
  --min-instances=1 \
  --service-account=int-service@$PROJECT_ID.iam.gserviceaccount.com \
  --set-env-vars=SFTP_HOST=$SFTP_HOST,SFTP_PORT=22,SFTP_USER=sftpuser,SFTP_PW=$SFTP_PW,BUCKET_NAME=$BUCKET
cd ../..

# Deploy integrations
cd integrations/sftp-integration
integrationcli integrations apply -f . -e dev --wait=true -p $PROJECT_ID -t $(gcloud auth print-access-token) -r $REGION --sa int-service --sp $PROJECT_ID
cd ../..

# WIP deploy the data API
# cd ./api-proxies/DataAPI-v1
# apigeecli apis create bundle -f apiproxy --name $API_NAME -o $PROJECT_ID -t $(gcloud auth print-access-token)
# apigeecli apis deploy -n $API_NAME -o $PROJECT_ID -e $APIGEE_ENV -t $(gcloud auth print-access-token) -s "mpservice@$PROJECT_ID.iam.gserviceaccount.com" --ovr
# cd ../..
