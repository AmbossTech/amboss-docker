# This script will run docker-compose-generator in a container to generate the yml files

If (-not ($AMBOSSGEN_DOCKER_IMAGE)) { $AMBOSSGEN_DOCKER_IMAGE = "amboss/docker-compose-generator" }

If ($AMBOSSGEN_DOCKER_IMAGE -eq "amboss/docker-compose-generator:local"){
	docker build docker-compose-generator -f docker-compose-generator/linuxamd64.Dockerfile --tag $AMBOSSGEN_DOCKER_IMAGE
} Else {
	docker pull $AMBOSSGEN_DOCKER_IMAGE
}

docker run -v "$(Get-Location)\Generated:/app/Generated" `
           -v "$(Get-Location)\docker-compose-generator\docker-fragments:/app/docker-fragments" `
           -e "AMBOSS_FULLNODE=$AMBOSS_FULLNODE" `
           -e "AMBOSSGEN_REVERSEPROXY=$AMBOSSGEN_REVERSEPROXY" `
           -e "AMBOSSGEN_ADDITIONAL_FRAGMENTS=$AMBOSSGEN_ADDITIONAL_FRAGMENTS" `
           -e "AMBOSSGEN_EXCLUDE_FRAGMENTS=$AMBOSSGEN_EXCLUDE_FRAGMENTS" `
           -e "AMBOSSGEN_LIGHTNING=$AMBOSSGEN_LIGHTNING" `
           -e "AMBOSSGEN_SUBNAME=$AMBOSSGEN_SUBNAME" `
           -e "AMBOSS_HOST_SSHAUTHORIZEDKEYS=$AMBOSS_HOST_SSHAUTHORIZEDKEYS" `
           --rm $AMBOSSGEN_DOCKER_IMAGE

If ($AMBOSSGEN_REVERSEPROXY -eq "nginx") {
    Copy-Item ".\Production\nginx.tmpl" -Destination ".\Generated"
}

If ($AMBOSSGEN_REVERSEPROXY -eq "traefik") {
    Copy-Item ".\Traefik\traefik.toml" -Destination ".\Generated"
    
    New-Item  ".\Generated\acme.json" -type file
}
