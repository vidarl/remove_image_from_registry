FROM docker

RUN apk update && apk add bash jq curl
ADD remove_image_from_registry.sh /remove_image_from_registry.sh

ENTRYPOINT ["/remove_image_from_registry.sh"]
