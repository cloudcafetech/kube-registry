#!/bin/bash
# Jfrog Registry Setup Script on KUBERNETES

PUB=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
JNS=kube-registry

DIR="$(pwd)/jfrog"
mkdir -p "${DIR}"

# Install Cfssl & Cfssljson
if ! command -v cfssl &> /dev/null;
then
 curl -s -L -o cfssl https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl_1.6.0_linux_amd64
 chmod +x cfssl
 mv cfssl /usr/local/bin/  
fi

if ! command -v cfssljson &> /dev/null;
then
 curl -s -L -o cfssljson https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssljson_1.6.0_linux_amd64
 chmod +x cfssljson
 mv cfssljson /usr/local/bin/  
fi

if ! command -v cfssl-certinfo &> /dev/null;
then
 curl -s -L -o cfssl-certinfo https://github.com/cloudflare/cfssl/releases/download/v1.6.0/cfssl-certinfo_1.6.0_linux_amd64
 chmod +x cfssl-certinfo
 mv cfssl-certinfo /usr/local/bin/  
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
fi

# Create Namespace
kubectl create ns $JNS

# First, create a Certificate Authority config file
cat << EOF > "${DIR}/ca-config.json"
{
    "signing": {
        "default": {
            "expiry": "43800h"
        },
        "profiles": {
            "server": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "43800h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            }
        }
    }
}
EOF

cat << EOF > "${DIR}/ca-csr.json"
{
    "CN": "My own CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "US",
            "L": "CA",
            "O": "My Company Name",
            "ST": "San Francisco",
            "OU": "Org Unit 1",
            "OU": "Org Unit 2"
        }
    ]
}
EOF

cat << EOF > "${DIR}/server.json"
{
    "CN": "jfregistry.$HIP.nip.io",
    "hosts": [
        "jfregistry.$PUB.nip.io",
        "jfregistry.$HIP.nip.io"
    ],
    "key": {
        "algo": "ecdsa",
        "size": 256
    },
    "names": [
        {
            "C": "US",
            "L": "CA",
            "ST": "San Francisco"
        }
    ]
}
EOF

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
cfssl gencert -initca "${DIR}/ca-csr.json" | cfssljson -bare "${DIR}/ca" -
cfssl gencert -ca="${DIR}/ca.pem" -ca-key="${DIR}/ca-key.pem" -config="${DIR}/ca-config.json" -profile=server "${DIR}/server.json" | cfssljson -bare "${DIR}/server"

# Create Kubernetes secrets
#kubectl create secret tls artifactory-tls --cert="${DIR}/server.pem" --key="${DIR}/server-key.pem" -n $JNS
if [ -e "certgen.sh" ]
then
 echo "File (certgen.sh) exists."
else
Wget 
fi
./certgen.sh
kubectl create secret tls artifactory-tls --cert=tls/server.crt --key=tls/server.key -n $JNS

# Setup deployment using Helm
helm repo add jfrog https://charts.jfrog.io
helm repo update
helm upgrade --install jfrog-container-registry -f "${DIR}/jfrog-values.yaml" --namespace $JNS jfrog/artifactory-jcr

# Create Kubernetes Ingress
kubectl create -f "${DIR}/ingress.yaml"  -n $JNS

exit

export JFROG="jfregistry.$HIP.nip.io"
docker pull nginx
docker login -u admin ${JFROG}
docker tag nginx:latest ${JFROG}/prod/nginx:latest
docker push ${JFROG}/prod/nginx:latest
