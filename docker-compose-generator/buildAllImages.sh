#!/bin/sh

REPO=amboss/docker-compose-generator

echo
echo
echo "------------------------------------------"
echo "Building images for" $REPO
echo "------------------------------------------"
echo
echo

git checkout master || exit
git pull || exit

START=`date +%s`

echo
echo
echo "------------------------------------------"
echo "Building amd64 image"
echo "------------------------------------------"
echo
echo

docker build --pull -t $REPO:latest-amd64 -f linuxamd64.Dockerfile .
docker push $REPO:latest-amd64

ENDAMD=`date +%s`

echo
echo
echo "------------------------------------------"
echo "Building arm32v7 image"
echo "------------------------------------------"
echo
echo

docker build --pull -t $REPO:latest-arm32v7 -f linuxarm32v7.Dockerfile .
docker push $REPO:latest-arm32v7

ENDARM32=`date +%s`

echo
echo
echo "------------------------------------------"
echo "Building arm64v8 image"
echo "------------------------------------------"
echo
echo

docker build --pull -t $REPO:latest-arm64v8 -f linuxarm64v8.Dockerfile .
docker push $REPO:latest-arm64v8

ENDARM64=`date +%s`

echo
echo
echo "------------------------------------------"
echo "Creating manifest"
echo "------------------------------------------"
echo
echo

docker manifest create --amend $REPO:latest $REPO:latest-amd64 $REPO:latest-arm32v7 $REPO:latest-arm64v8
docker manifest annotate $REPO:latest $REPO:latest-amd64 --os linux --arch amd64
docker manifest annotate $REPO:latest $REPO:latest-arm32v7 --os linux --arch arm --variant v7
docker manifest annotate $REPO:latest $REPO:latest-arm64v8 --os linux --arch arm64 --variant v8
docker manifest push $REPO:latest -p

RUNTIME=$((ENDAMD-START))
RUNTIME1=$((ENDARM32-ENDAMD))
RUNTIME2=$((ENDARM64-ENDARM32))

git checkout master
git pull

echo
echo
echo "------------------------------------------"
echo "DONE"
echo "------------------------------------------"
echo
echo
echo "Finished building and pushing images for" $REPO:latest
echo
echo "amd64 took" $RUNTIME "seconds"
echo "arm32v7 took" $RUNTIME1 "seconds"
echo "arm64v8 took" $RUNTIME2 "seconds"
echo
echo