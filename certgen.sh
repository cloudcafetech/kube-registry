#!/bin/sh
# Cretificate Generate Script for Jfrog Registry

PUB=`curl http://169.254.169.254/latest/meta-data/public-ipv4`
HIP=`ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1`
JNS=kube-registry

mkdir tls
cd tls

# Create the conf file
cat > openssl.cnf << EOF
[req]
default_bits = 2048
encrypt_key  = no
default_md   = sha256
prompt       = no
utf8         = yes
distinguished_name = req_distinguished_name
req_extensions     = v3_req
[req_distinguished_name]
C = IN
ST = WB
L = Kolkata
O = CloudCafe
OU = ITDivision
CN = jfregistry.$HIP.nip.io
[v3_req]
basicConstraints     = CA:FALSE
subjectKeyIdentifier = hash
keyUsage             = digitalSignature, keyEncipherment
extendedKeyUsage     = clientAuth, serverAuth
subjectAltName       = @alt_names
[alt_names]
DNS.1 = *.$JNS.svc.cluster.local
DNS.2 = jfregistry.$PUB.nip.io
DNS.3 = jfregistry.$HIP.nip.io
DNS.4 = localhost
IP = 127.0.0.1
EOF

# Self signed root CA cert
openssl req -nodes -x509 -days 3650 -newkey rsa:2048 -keyout ca.key -out ca.crt -subj "/C=IN/ST=WB/L=Kolkata/O=CloudCafe/OU=ITDivision/CN=jfregistry.$HIP.nip.io"

# Generate server cert to be signed
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr -config openssl.cnf

# Sign the server cert
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -extensions v3_req -extfile openssl.cnf 

# Create server PEM file
cat server.key server.crt > server.pem

# Generate client cert to be signed
openssl genrsa -out client.key 2048
openssl req -new -key client.key -out client.csr -config openssl.cnf

# Sign the client cert
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAserial ca.srl -out client.crt -extensions v3_req -extfile openssl.cnf 

# Create client PEM file
cat client.key client.crt > client.pem
