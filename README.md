# Kubernetes Private Registry
Kubernetes Registry using Jfrog

- Setup

```
wget https://raw.githubusercontent.com/cloudcafetech/kube-registry/main/k8s-setup.sh
chmod +x k8s-setup.sh
./k8s-setup.sh k3d
```

- EULA

```curl -XPOST -vku admin:password https://jfregistry.172.31.44.213.nip.io/artifactory/ui/jcr/eula/accept```

- Testing

```
export JFROG="jfregistry.$HIP.nip.io"
docker pull nginx
docker login -u admin -p password ${JFROG}
docker tag nginx:latest ${JFROG}/prod/nginx:latest
docker push ${JFROG}/prod/nginx:latest
```

[Ref#1](https://next.nutanix.com/community-blog-154/deploying-jfrog-container-registry-on-nutanix-karbon-33739)
