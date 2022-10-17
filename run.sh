#!/bin/bash
# install & configure git and Docker comppose and Jenkins and minikube
DOCKER_COMPOSE="v2.9.0"
KUBECTL="v1.23.2"
apt_first=("ca-certificates" "curl" "gnupg" "lsb-release" "git" "conntrack")
apt_docker=("docker-ce" "docker-ce-cli" "containerd.io" "docker-compose-plugin")
flog() {
   [[ $1 -eq 0 ]] && printf "%s: [SUCCESS] %s\n" "$(date)" "$2" || printf "%s: [ERROR] %s\n" "$(date)" "$2" >> /tmp/run.log
}

fapt() {
    for apt_name in $i
    do
        apt-get -yq install $apt_name
        flog "$?" "install $apt_name"
    done
}

fcurl() {
    [[ -f "/usr/local/bin/$1" ]] && flog "$?" "$1 already exist" ||  curl -L $2 -o /usr/local/bin/$1 && flog "$?" "install $1";chmod +x /usr/local/bin/$1
}

fsystemctl() {
    if [[ "$1" == "enable" ]] 
    then
       [[ -f "/etc/systemd/system/multi-user.target.wants/$2" ]] && flog "$?" "$2 already exist $1" || systemctl $1 $2 &&  flog "$?" "$1 $2" 
    else
         systemctl $1 $2 &&  flog "$?" "$1 $2"  
    fi 
}
flog "$?" "start setup"

apt-get update
fapt "${apt_first[@]}" 

fcurl "docker-compose" "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE}/docker-compose-`uname -s`-`uname -m`"
fcurl "minikube" "https://github.com/kubernetes/minikube/releases/download/${KUBECTL}/minikube-linux-amd64 "
fcurl "kubectl" "https://dl.k8s.io/release/${KUBECTL}/bin/linux/amd64/kubectl"

[[ -f "/etc/apt/keyrings/docker.gpg" ]] && flog "$?" "keyrings gpg docker already exist" || curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && flog "$?" "install keyrings gpg docker"

[[ -f "/etc/apt/keyrings/docker.gpg" ]] && echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && flog "$?" "install source list docker"

fapt "${apt_docker[@]}" 

[[ -f "/etc/systemd/system/docker-compose@.service" ]] &&  flog "$?" "Template docker-compose already exist" || cat > /etc/systemd/system/docker-compose@.service <<-EOF
[Unit]
Description=%i service with docker compose
PartOf=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=true
WorkingDirectory=/etc/docker/compose/%i
ExecStart=/usr/local/bin/docker-compose up -d --remove-orphans
ExecStop=/usr/local/bin/docker-compose down

[Install]
WantedBy=multi-user.target
EOF
flog "$?" "install Template docker-compose"

[[ -f "/etc/systemd/system/minikube.service" ]] &&  flog "$?" "Template minikube already exist" ||  cat > /etc/systemd/system/minikube.service <<-EOF
[Unit]
Description=Minikube Cluster
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/minikube start --driver=none
RemainAfterExit=true
ExecStop=/usr/local/bin/minikube stop

[Install]
WantedBy=multi-user.target
EOF
flog "$?" "install Template minikube"

[[ -f "/etc/docker/compose/jenkins/docker-compose.yml" ]] &&  flog "$?" "Template docker-compose already exist" || cat > /etc/docker/compose/jenkins/docker-compose.yml <<-EOF
version: '3.8'
services:
    jenkins:
    image: jenkins/jenkins:lts
    privileged: true
    user: root
    ports:
        - 80:8080
        - 50000:50000
    container_name: jenkins
    volumes:
        - /home/debian/jenkins:/var/jenkins_home
        - /var/run/docker.sock:/var/run/docker.sock
        - /usr/local/bin/docker:/usr/local/bin/docker
EOF
flog "$?" "install Template Jenkins docker-compose"


fsystemctl "enable" "minikube.service"
fsystemctl "enable" "docker-compose@jenkins"

fsystemctl "start" "docker-compose@jenkins"
/usr/local/bin/minikube start --driver=none && flog "$?" "start minikube"
flog "$?" "End setup"
