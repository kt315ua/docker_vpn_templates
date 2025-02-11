# Build image

docker build -t l2tp_ipsec:latest .

# Run container

## Foreground
```
docker run --privileged --cap-add=NET_ADMIN -it --env-file env-file -v /lib/modules:/lib/modules l2tp_ipsec:latest
```
## Background
```
docker run -d --privileged --cap-add=NET_ADMIN -it --env-file env-file -v /lib/modules:/lib/modules l2tp_ipsec:latest
```
## Connect to running container by IMAGE name
```docker exec -it $(docker ps -qf "ancestor=l2tp_ipsec:latest") bash```

## Check running docker containers
```
docker ps
docker stats
```
