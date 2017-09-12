FROM alpine

RUN apk update && apk add bash
ADD remove_image_from_registry.sh /remove_image_from_registry.sh

ENTRYPOINT ["/remove_image_from_registry.sh"]
