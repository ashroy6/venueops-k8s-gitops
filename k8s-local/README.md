# VenueOps Local Kubernetes Deployment

This folder is for local kubeadm deployment only.

It does not modify:
- docker-compose.yml
- infra/helm
- infra/terraform
- apps/web original files

Phase 1 services:
- venueops-web
- venueops-api
- venueops-ingestion-api

Storage:
- hostPath local PersistentVolume on kl-worker-1
- path: /opt/venueops/data
- mounted as /data in api and ingestion-api

Access:
- kubectl port-forward svc/venueops-web 3000:80 -n venueops
- browser: http://127.0.0.1:3000

Image tags:
- ashroy6/venueops-web:kube-local
- ashroy6/venueops-api:kube-local
- ashroy6/venueops-ingestion-api:kube-local
