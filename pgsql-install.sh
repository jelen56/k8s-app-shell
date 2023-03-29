#!/usr/bin/env bash
HOST_NAME=$(hostname -f)
PGSQL_PV_PATH="${PGSQL_PV_PATH:-$HOME/k8s/postgres/storage}"
PGSQL_CONFIG_PATH="${PGSQL_CONFIG_PATH:-$HOME/k8s/postgres/config}"
PGSQL_USER="root"
PGSQL_PWD="root666"
PGSQL_DATA_PATH="${PGSQL_DATA_PATH:-$HOME/k8s/postgres/data}"
PGSQL_LOG_PATH="${PGSQL_LOG_PATH:-$HOME/k8s/postgres/log}"
#it will choose the lastest version to install defaultly,if u want to install the specified version,just sign it like: POSTGRES_VERSION="${POSTGRES_VERSION:-9.5}"
POSTGRES_VERSION="${POSTGRES_VERSION:-}"
declare -A ALL_APPLY_FILES
declare -A FAIL_COMMANDS

function is::error() {
    local error="$(echo $1 | grep -E "Error |error |Invalid |invalid ")"
    if [[ "$error" != "" ]];then
        return 1
    fi
    return 0
}

function apply() {
    local yamlFile=$1
    echo "kubectl apply -f [$yamlFile]"
    kubectl apply -f $yamlFile
    is::error $?
    if [ $? -eq 1 ]; then
        FAIL_COMMANDS[${#FAIL_COMMANDS}]=$yamlFile
    fi    
}

#local storage(no-provisioner) storageClass
function build::storageClass() {
  touch "${ALL_APPLY_FILES["storageClass"]}" 
  tee "${ALL_APPLY_FILES["storageClass"]}" <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: database
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
apply "${ALL_APPLY_FILES["storageClass"]}" 
}

function build::pgNameSpace() {
  touch "${ALL_APPLY_FILES["pgNameSpace"]}" 
  tee "${ALL_APPLY_FILES["pgNameSpace"]}" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: postgres
EOF
  apply "${ALL_APPLY_FILES["pgNameSpace"]}" 
}

function build::pgConfigMap() {
  touch "${ALL_APPLY_FILES["pgConfigMap"]}" 
  tee "${ALL_APPLY_FILES["pgConfigMap"]}" <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-config
  namespace: postgres
  labels:
    app: postgres
data:
  POSTGRES_DB: master
  POSTGRES_USER: $PGSQL_USER
  POSTGRES_PASSWORD: $PGSQL_PWD
EOF
apply "${ALL_APPLY_FILES["pgConfigMap"]}" 
}

#pv
function build::persistentVolume() {
  touch "${ALL_APPLY_FILES["persistentVolume"]}" 
  tee "${ALL_APPLY_FILES["persistentVolume"]}" <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pgsql-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: database
  local:
    path: $PGSQL_PV_PATH
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $HOST_NAME
EOF
apply "${ALL_APPLY_FILES["persistentVolume"]}"
}

#StatefulSet and pvc(config by volumeClaimTemplates)
function build::pgStatefulset() {
  local image_version
  if [ -z $OSTGRES_VERSION ];then 
      image_version="postgres ""$POSTGRES_VERSION"
  else
      image_version="postgres"
  fi 
  touch "${ALL_APPLY_FILES["pgStatefulset"]}" 
  tee "${ALL_APPLY_FILES["pgStatefulset"]}" <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres-statefulset
  namespace: postgres
spec:
  serviceName: postgres-service
  replicas: 1
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 1       
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: $image_version
          imagePullPolicy: IfNotPresent
          envFrom:
            - configMapRef:
                name: postgres-config
          ports:
            - containerPort: 5432
              name: postgredb
          volumeMounts:
            - name: mylocaltime
              mountPath: /etc/localtime
            - name: pgsql-pvc
              mountPath: $PGSQL_DATA_PATH
              subPath: postgres
            - name: pgsql-pvc  
              mountPath: $PGSQL_LOG_PATH
      volumes:
        - name: mylocaltime
          hostPath:
            path: /etc/localtime
            type: File              
  volumeClaimTemplates:
  - apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: pgsql-pvc
      namespace: postgres
      labels:
        app: postgres
    spec:
      accessModes:
      - ReadWriteOnce
      storageClassName: database
      volumeName: pgsql-pv
      volumeMode: Filesystem
      resources:
        requests:
          storage: 1Gi
EOF
apply "${ALL_APPLY_FILES["pgStatefulset"]}"
}

function build::pgService() {
  touch "${ALL_APPLY_FILES["pgService"]}" 
  tee "${ALL_APPLY_FILES["pgService"]}" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: postgres-service
  namespace: postgres
  labels:
    app: postgres
spec:
  type: NodePort 
  ports:
    - port: 5432
      name: postgres
      nodePort: 35432  
  selector:
    app: postgres
EOF
apply "${ALL_APPLY_FILES["pgService"]}"
}

function init::pgsql() {
    
    build::pgNameSpace
    
    build::storageClass

    build::persistentVolume

    build::pgConfigMap

    build::pgStatefulset

    build::pgStatefulset

    build::pgService

}

function check::result() {
  fail::check
  if [ $? -eq 0 ];then 
    reset
  else  
    echo "successful install..."
    kubectl get pod -n postgres
    kubectl get svc -n postgres
    kubectl exec -it -n postgres postgres-statefulset-0 -- psql -h localhost -U $PGSQL_USER --password -p 5432 master
  fi
}

function fail::check(){
  echo "doing fail::check"
  if [ ${#FAIL_COMMANDS} -eq 0 ];then
    return 1
  fi  
  return 0
}

function reset() {
    echo "doing reset..."
    for errorIndex in "${!FAIL_COMMANDS[@]}"
    do
      echo "${FAIL_COMMANDS[$errorIndex]} apply fail..."
    done    
    for index in "${!ALL_APPLY_FILES[@]}"
    do
      echo "deleting: ${ALL_APPLY_FILES[$index]}..."
      kubectl delete -f "${ALL_APPLY_FILES[$index]}"
    done  
    delete::data
    echo "delete all data..."
    exit 1
}

function delete::data(){
  echo "doing delete::data"
  rm -rf $PGSQL_PV_PATH
  rm -rf $PGSQL_CONFIG_PATH
  rm -rf $PGSQL_DATA_PATH
  rm -rf $PGSQL_LOG_PATH
}

function init::base(){
  mkdir -p $PGSQL_PV_PATH
  mkdir -p $PGSQL_CONFIG_PATH
  mkdir -p $PGSQL_DATA_PATH
  mkdir -p $PGSQL_LOG_PATH
  ALL_APPLY_FILES["storageClass"]="$PGSQL_CONFIG_PATH/storageClass.yaml"
  ALL_APPLY_FILES["pgNameSpace"]="$PGSQL_CONFIG_PATH/pgNameSpace.yaml"
  ALL_APPLY_FILES["pgConfigMap"]="$PGSQL_CONFIG_PATH/pgConfigMap.yaml"
  ALL_APPLY_FILES["persistentVolume"]="$PGSQL_CONFIG_PATH/persistentVolume.yaml"
  ALL_APPLY_FILES["pgStatefulset"]="$PGSQL_CONFIG_PATH/pgStatefulset.yaml"
  ALL_APPLY_FILES["pgService"]="$PGSQL_CONFIG_PATH/pgService.yaml"
}

function init() {
    init::pgsql
    check::result
}

function help(){
  local me="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
  echo "run 'bash $me init' to install postgres
   or 'bash $me reset' to delete all data about postgres"
  exit 1
}

function do::main(){
  if [[ "${INIT_COMMAND:-}" == "1" ]]; then
    init
  elif [[ "${RESET_COMMAND:-}" == "1" ]]; then
    reset  
  else
    help  
  fi  
}

init::base

[ "$#" == "0" ] && help
while [ "${1:-}" != "" ]; do
  case $1 in
  init)
    INIT_COMMAND=1
    ;;
  reset)
    RESET_COMMAND=1
    ;;
  *)
    help
    ;;
  esac
  shift
done

do::main
