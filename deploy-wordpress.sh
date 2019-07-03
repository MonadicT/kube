#!/bin/sh

# Deploy mysql
kubectl apply -f wordpress/mysql-secret.yml
kubectl apply -f wordpress/pvc-wp-mysql.yml
kubectl apply -f wordpress/deploy-wp-mysql.yml
kubectl apply -f wordpress/svc-wp-mysql.yml

# Deploy wordpress fe
kubectl apply -f wordpress/pvc-wp-fe.yml
kubectl apply -f wordpress/deploy-wp-frontend.yml
kubectl apply -f wordpress/deploy-wp-frontend.yml

kubectl apply -f  wordpress/service-wp.yml
