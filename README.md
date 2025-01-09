# alpine-docker-compose-install
为alpine系统安装docker及docker compose的一键脚本，兼容各个版本的alpine系统

1.创建临时文件夹

mkdir -p docker_install_tmp && cd docker_install_tmp

2.下载

wget https://raw.githubusercontent.com/Frischman/alpine-docker-compose-install/main/alpine-docker-install.sh -O install_docker_compose.sh

3.赋权

chmod +x install_docker_compose.sh

4.执行

./install_docker_compose.sh

5.删除

rm -rf docker_install_tmp
