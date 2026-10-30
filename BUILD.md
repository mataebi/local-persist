# Building the plugin in a copntainer (no installation of go needed)

Run the following on the command line

```
docker run --rm \
  -v "$PWD":/app \
  -w /app \
  golang:1.22 \
  go build -o docker-volume-local-persist .
```

The binary appears at ./docker-volume-local-persist on the host (it's a Linux binary built in a Linux container).
