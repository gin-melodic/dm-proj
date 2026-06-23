FROM golang:1.25-alpine AS builder

WORKDIR /src
COPY dm-server/go.mod dm-server/go.sum ./
RUN go mod download
COPY dm-server/ ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/dm-server ./main.go

FROM alpine:3.22

RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /out/dm-server ./dm-server
COPY dm-server/resource/ ./resource/
COPY docker/dm-server.config.yaml ./manifest/config/config.yaml
RUN mkdir -p /app/logs/sql

EXPOSE 8080
CMD ["./dm-server"]
