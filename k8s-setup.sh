#!/bin/bash
# Install KIND KUBERNETES

CLUSTER0=kube-central
CLUSTER1=kube-one
CTXTYPE=$1
CTXNUM=$2

if [[ ! $CTXTYPE =~ ^( |kind|k3d)$ ]]; then 
 echo "Usage: k8s-setup.sh <kind or k3d>"
 echo "Example: k8s-setup.sh kind/k3d"
 exit
fi

PUB=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
MinIO=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
velver=v1.4.2
find . -type f -exec sed -i -e "s/172.31.14.138/$HIP/g" {} \;
find . -type f -exec sed -i -e "s/3.16.154.209/$PUB/g" {} \;

# Install packages
echo "Installing Packges"
yum install -q -y git curl wget bind-utils jq httpd-tools zip unzip nfs-utils dos2unix telnet java-1.8.0-openjdk

# Install Docker
if ! command -v docker &> /dev/null;
then
  echo "MISSING REQUIREMENT: docker engine could not be found on your system. Please install docker engine to continue: https://docs.docker.com/get-docker/"
  echo "Trying to Install Docker..."
  if [[ $(uname -a | grep amzn) ]]; then
    echo "Installing Docker for Amazon Linux"
    amazon-linux-extras install docker -y
    systemctl enable docker;systemctl start docker
    docker ps -a
  else
    curl -s https://releases.rancher.com/install-docker/19.03.sh | sh
    systemctl enable docker;systemctl start docker
    docker ps -a
  fi    
fi

# Setup for insecure registry
cat << EOF > /etc/docker/daemon.json
{
  "insecure-registries" : ["jfregistry.$HIP.nip.io"]
}
EOF
systemctl restart docker

# Install K3D
if ! command -v k3d &> /dev/null;
then
 echo "Installing K3D"
 wget -q -O - https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash
fi

# Install KIND
if ! command -v kind &> /dev/null;
then
 echo "Installing Kind"
 curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.10.0/kind-linux-amd64
 chmod +x ./kind; mv ./kind /usr/local/bin/kind
fi

# Install Kubectl
if ! command -v kubectl &> /dev/null;
then
 echo "Installing Kubectl"
 K8S_VER=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
 wget -q https://storage.googleapis.com/kubernetes-release/release/$K8S_VER/bin/linux/amd64/kubectl
 chmod +x ./kubectl; mv ./kubectl /usr/bin/kubectl
 echo "alias oc=/usr/bin/kubectl" >> /root/.bash_profile
fi 

# Install Consul
if ! command -v consul &> /dev/null;
then
 echo "Installing Consul"
 curl https://releases.hashicorp.com/consul/1.9.8/consul_1.9.8_linux_amd64.zip -o consul_1.9.8_linux_amd64.zip
 unzip consul_1.9.8_linux_amd64.zip
 chmod +x consul
 mv consul /usr/local/bin/consul
 rm -rf consul_1.9.8_linux_amd64.zip
fi

# Install Vault
if ! command -v vault &> /dev/null;
then
 echo "Installing Vault"
 curl https://releases.hashicorp.com/vault/1.7.3/vault_1.7.3_linux_amd64.zip -o vault_1.7.3_linux_amd64.zip
 unzip vault_1.7.3_linux_amd64.zip
 chmod +x vault
 mv vault /usr/local/bin/vault
 rm -rf vault_1.7.3_linux_amd64.zip
fi

# Install Cfssl & Cfssljson
curl -s -L -o cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl_1.6.0_linux_amd64
curl -s -L -o cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssljson_1.6.0_linux_amd64
curl -s -L -o cfssl-certinfo https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl-certinfo_1.6.0_linux_amd64
chmod +x cfssl*
mv cfssl* /usr/local/bin/

# Install CTOP
if ! command -v ctop &> /dev/null;
then
 echo "Installing CTOP"
 sudo wget https://github.com/bcicen/ctop/releases/download/0.7.6/ctop-0.7.6-linux-amd64 -O /usr/local/bin/ctop
 sudo chmod +x /usr/local/bin/ctop
fi

# Download files
https://raw.githubusercontent.com/cloudcafetech/kube-registry/main/jf-setup.sh
chmod +x jf-setup.sh

if [[ "$CTXTYPE" == "kind" ]]; then
# Kubernetes Cluster Creation
for CTX in $CLUSTER0 $CLUSTER1
do
cat <<EOF > kind-kube-$CTX.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerPort: 19091
  apiServerAddress: $HIP
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 80
  - containerPort: 30443
    hostPort: 443
  extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
- role: worker
EOF
done

# Cluster Creation using KIND
cp kube-kind-ingress.yaml kube-kind-ingress-$CLUSTER0.yaml
cp kube-kind-ingress.yaml kube-kind-ingress-$CLUSTER1.yaml
sed -i "s/30080/31080/g" kube-kind-ingress-$CLUSTER1.yaml
sed -i "s/30443/31443/g" kube-kind-ingress-$CLUSTER1.yaml
sed -i "s/hostPort: 80/hostPort: 8080/g" kind-kube-$CLUSTER1.yaml
sed -i "s/hostPort: 443/hostPort: 6443/g" kind-kube-$CLUSTER1.yaml
sed -i "s/30080/31080/g" kind-kube-$CLUSTER1.yaml
sed -i "s/30443/31443/g" kind-kube-$CLUSTER1.yaml
sed -i "s/19091/19092/g" kind-kube-$CLUSTER1.yaml
sed -i '$d' kind-kube-$CLUSTER1.yaml
kind create cluster --name $CLUSTER0 --kubeconfig $CLUSTER0-kubeconf --config kind-kube-$CLUSTER0.yaml --wait 2m

if [[ "$CTXNUM" == "2" ]]; then
 kind create cluster --name $CLUSTER1 --kubeconfig $CLUSTER1-kubeconf --config kind-kube-$CLUSTER1.yaml --wait 2m
fi

# Setup Ingress
for CTX in $CLUSTER0 $CLUSTER1
do
 echo "Setting Ingress for $CTX"
 export KUBECONFIG=$CTX-kubeconf
 #kubectl apply -f kube-kind-ingress-$CTX.yaml
 sleep 15
 kubectl delete -A ValidatingWebhookConfiguration ingress-nginx-admission
done

else
# Cluster Creation using K3D
cat <<EOF > helm-ingress-nginx.yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: ingress-controller-nginx
  namespace: kube-system
spec:
  repo: https://kubernetes.github.io/ingress-nginx
  chart: ingress-nginx
  version: 3.7.1
  targetNamespace: kube-system
EOF
k3d cluster create $CLUSTER0 --api-port $HIP:6551 -p 80:80@loadbalancer -p 443:443@loadbalancer --k3s-server-arg '--no-deploy=traefik' --volume "$(pwd)/helm-ingress-nginx.yaml:/var/lib/rancher/k3s/server/manifests/helm-ingress-nginx.yaml"
k3d kubeconfig get $CLUSTER0 >$CLUSTER0-kubeconf

if [[ "$CTXNUM" == "2" ]]; then
 k3d cluster create $CLUSTER1 --api-port $HIP:6552 -p 8080:80@loadbalancer -p 6443:443@loadbalancer --k3s-server-arg '--no-deploy=traefik' --volume "$(pwd)/helm-ingress-nginx.yaml:/var/lib/rancher/k3s/server/manifests/helm-ingress-nginx.yaml"
 k3d kubeconfig get $CLUSTER1 >$CLUSTER1-kubeconf
fi
fi

# Setup Helm Chart
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 > get_helm.sh
chmod 700 get_helm.sh
./get_helm.sh

# Merging Kubeconfig
export KUBECONFIG=$CLUSTER0-kubeconf:$CLUSTER1-kubeconf
kubectl config view --raw > merge-config
yes | cp -rf merge-config ~/.kube/config

# Install Krew
set -x; cd "$(mktemp -d)" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/krew.{tar.gz,yaml}" &&
  tar zxvf krew.tar.gz &&
  KREW=./krew-"$(uname | tr '[:upper:]' '[:lower:]')_amd64" &&
  "$KREW" install --manifest=krew.yaml --archive=krew.tar.gz &&
  "$KREW" update

export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

kubectl krew install modify-secret
kubectl krew install ctx
kubectl krew install ns
kubectl krew install cost

echo 'export PATH="${PATH}:${HOME}/.krew/bin"' >> /root/.bash_profile
exit
