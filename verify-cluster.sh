#!/bin/sh

echo Nodes\\n-----
kubectl get nodes -o wide

echo \\nPods in kube-system\\n------------
kubectl get pods -n kube-system -o wide


echo \\nDNS lookup\\n----------
kubectl run -it --rm --image=busybox:1.28 --restart=Never -- busybox nslookup kubernetes.default
kubectl run -it --rm --image=busybox:1.28 --restart=Never -- busybox nslookup google.com

#kubectl run -it --rm --image=mysql:5.6 --restart=Never mysql-client -- mysql -h mysql -ppassword
