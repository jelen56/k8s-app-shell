# k8s-apps-shell
#### This is a script repository related to k8s common services/apps deployment, use, and configuration, such as postgresql,developed by using shell scripts

### the apps support list:
- postgresql
- cri-dockerd
- ...(coming soon)

### usage:
- postgresql:
  - `init`: `bash pgsql-install.sh init`
  - `reset`: `bash pgsql-install.sh reset`,**NOTE**:`reset` means deleting the related datas and resource(such as services),Generally used when you want to reinstall postgresql

- cri-dockerd:
  - `init`:`bash cri-dockerd-install.sh init`
  - `reset`:`bash cri-dockerd-install.sh reset`,**NOTE**:`reset` means deleting the related datas and resource(such as services),Generally used when you want to reinstall postgresql

  
