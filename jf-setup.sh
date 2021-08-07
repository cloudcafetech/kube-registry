#!/bin/bash
# Jfrog Registry Setup Script on KUBERNETES

PUB=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
JNS=kube-registry

DIR="$(pwd)/jfrog"
mkdir -p "${DIR}"

# Install Openssl
if ! command -v openssl &> /dev/null;
then
 yum install -q -y openssl  
fi

if [ -e "/etc/docker/daemon.json" ]
then
 echo "File (/etc/docker/daemon.json) exists."
else
cat << EOF > /etc/docker/daemon.json
{
  "insecure-registries" : ["jfregistry.$HIP.nip.io"]
}
EOF
systemctl restart docker
sleep 45
fi

# Create Namespace
kubectl create ns $JNS

# Create Custom helm value for jfrog registry
cat << EOF > "${DIR}/jfrog-values.yaml"
artifactory:
  artifactory:
    persistence:
      size: 5Gi
  nginx:
    enabled: true
    tlsSecretName: artifactory-tls
    service:
      type: ClusterIP
EOF

# Create Ingress for jfrog registry
cat << EOF > "${DIR}/ingress.yaml"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: jfrog
  annotations:
    kubernetes.io/ingress.class: nginx
    kubernetes.io/tls-acme: 'true'
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    nginx.ingress.kubernetes.io/proxy-body-size: 50m    
spec:
  tls:
    - hosts:
      - jfregistry.$PUB.nip.io
      - jfregistry.$HIP.nip.io
      secretName: artifactory-tls
  rules:
    - host: jfregistry.$PUB.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: jfrog-container-registry-artifactory-nginx
                port:
                  number: 443
    - host: jfregistry.$HIP.nip.io
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: jfrog-container-registry-artifactory-nginx
                port:
                  number: 443  
EOF

# Generate Certificates
if [ -e "certgen.sh" ]
then
 echo "File (certgen.sh) exists."
else
 wget https://raw.githubusercontent.com/cloudcafetech/kube-registry/main/certgen.sh
 chmod +x certgen.sh
fi
./certgen.sh

# Create Kubernetes secrets
kubectl create secret tls artifactory-tls --cert=tls/server.crt --key=tls/server.key -n $JNS

# Setup deployment using Helm
helm repo add jfrog https://charts.jfrog.io
helm repo update
helm upgrade --install jfrog-container-registry -f "${DIR}/jfrog-values.yaml" --namespace $JNS jfrog/artifactory-jcr

# Create Kubernetes Ingress
kubectl create -f "${DIR}/ingress.yaml"  -n $JNS
