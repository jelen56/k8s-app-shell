#!/usr/bin/env bash
CRI_VERSION="${CRI_VERSION:-https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.1/cri-dockerd-0.3.1-3.el7.x86_64.rpm}"
CRI_TMP_FOLD="${CRI_FOLD:-/tmp/cri-docker}"
CRI_TMP_FILE_PATH="${CRI_TMP_FILE_PATH:-$CRI_TMP_FOLD/cri-dockerd.rpm}"
IMAGES_REPOSITORY="${IMAGES_REPOSITORY:-registry.aliyuncs.com/google_containers}"

function check::fold() {
  if [ $# -lt 1 ];then
    echo "fileFold arg is need"
    return 0
  fi
 if [ -d $1 ]; then
   return 1 
 fi
 return 0
}

function check::file() {
  if [ $# -lt 1 ];then
    echo "fileFold arg is need"
    return 0
  fi
  if [ -f $1 ]; then
    return 1 
  fi
}

function check::fold() {
  if [ $# -lt 1 ];then
    echo "fileFold arg is need"
    return 0
  fi
 if [ -d $1 ]; then
   return 1 
 fi
 return 0
}

function check::file() {
  if [ $# -lt 1 ];then
    echo "fileFold arg is need"
    return 0
  fi
  if [ -f $1 ]; then
    return 1 
  fi
}

function install::cli_docker() {
    if ! type cri-dockerd >/dev/null 2>&1; then
        download::cri_docker
        echo "begin to install cri-dockerd,packagePath:${CRI_TMP_FILE_PATH}"
        rpm -i ${CRI_TMP_FILE_PATH}
        mv /usr/bin/cri-dockerd /usr/local/bin/cri-dockerd
        echo "install cri-dockerd finish..."
    else
        echo "cri-dockerd has already installed"
    fi
    echo "start to config cri-dockerd..."
    edit::cri_docker_service
    edit::cri_docker_socket
    echo "config end"
    reload::config
}

function reload::config() {
    echo "start to reload config..."
    systemctl daemon-reload
    systemctl start cri-docker.service
    systemctl enable cri-docker.service
    systemctl enable --now cri-docker.socket
    systemctl is-active cri-docker.socket
    echo "end to reload config..."
    echo $(cri-dockerd --version)
}

function download::cri_docker() {
   check::file $CRI_TMP_FILE_PATH
    if [ $? == 0 ];
    then
      echo "start to download cri_docker"
      check::net ${CRI_TMP_FILE_PATH} ${CRI_VERSION}
      echo "success to download cri_docker"
    else
      echo "u have already downloaded the cri_docker in $CRI_TMP_FILE_PATH"
    fi
}

function edit::cri_docker_service() {
    local cri_docker_service=/etc/systemd/system/cri-docker.service
    check::file "$cri_docker_service"
    local result=$?
    if [ $result == 1 ];then
      echo "backup ur $cri_docker_service in same fold...."
      cp $cri_docker_service /etc/systemd/system/cri-docker.service.bak
    fi
    tee /etc/systemd/system/cri-docker.service << EOF
    [Unit]
    Description=CRI Interface for Docker Application Container Engine
    Documentation=https://docs.mirantis.com
    After=network-online.target firewalld.service docker.service
    Wants=network-online.target
    Requires=cri-docker.socket
    [Service]
    Type=notify
    ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd:// --network-plugin=cni --pod-infra-container-image=$IMAGES_REPOSITORY/pause:3.7
    ExecReload=/bin/kill -s HUP \$MAINPID
    TimeoutSec=0
    RestartSec=2
    Restart=always
    StartLimitBurst=3
    StartLimitInterval=60s
    LimitNOFILE=infinity
    LimitNPROC=infinity
    LimitCORE=infinity
    TasksMax=infinity
    Delegate=yes
    KillMode=process
    [Install]
    WantedBy=multi-user.target
EOF
}

function edit::cri_docker_socket(){
  local cri_docker_socket=/etc/systemd/system/cri-docker.socket
  check::file "$cri_docker_socket"
  local result=$?
  if [ $result == 1 ];then
    echo "backup ur $cri_docker_socket in same fold...."
    cp $cri_docker_socket /etc/systemd/system/cri-docker.socket.bak
  fi
  tee /etc/systemd/system/cri-docker.socket << EOF
  [Unit]
  Description=CRI Docker Socket for the API
  PartOf=cri-docker.service
  [Socket]
  ListenStream=%t/cri-dockerd.sock
  SocketMode=0660
  SocketUser=root
  SocketGroup=docker
  [Install]
  WantedBy=sockets.target
EOF
}

function uninstall::cli_docker(){
  if type cri-dockerd >/dev/null 2>&1; then
    echo "start uninstall cri-dockerd"
    rpm -e cri_docker
    rm -rf /usr/local/bin/cri-dockerd
    cat /dev/null > /etc/systemd/system/cri-docker.service
    cat /dev/null > /etc/systemd/system/cri-docker.socket
  fi  
}

function init::base() {
    check::fold $CRI_TMP_FOLD
    if [ $? -eq 0 ];then
        echo "create $CRI_TMP_FOLD"
        mkdir -p $CRI_TMP_FOLD
    fi
}

function init() {
    install::cli_docker
}

function reset() {
    uninstall::cli_docker
    rm -rf $CRI_TMP_FILE_PATH
}

function help(){
  local me="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
  echo "run 'bash $me init' to install cri-dockerd
   or 'bash $me reset' to delete all data about cri-dockerd"
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
