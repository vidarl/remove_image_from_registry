# Remove a image from a remote docker registry

This bash script makes it possible to delete a image from a docker registry v2
Don't be afraid to delete images which contains layers used by other images. The docker registry backend will automatically detect that and keep those layers.

## Quick start

```sh
 $ docker run --rm -ti vidarl/remove_image_from_registry -u username -p myregistry:5000/myrepo/myimage:latest
```

## This script requires:
* Docker registry (v2)
* Registry must use token based authentication
   Check out https://github.com/cesanta/docker_auth for a nice authentication server.
* Deletion must be explicitly enabled on the registry server
  * Use environment variable REGISTRY_STORAGE_DELETE_ENABLED=true
  * Or storage.delete.enabled=true in [config.yml](https://docs.docker.com/registry/configuration/#delete).

# Usage

```sh
 $ ./remove_image_from_registry.sh [OPTIONS] [IMAGE]

IMAGE
 Image name has the format registryhost:port/reposityry/imagename:version
 For instance : mydockerregistry:5000/myrepo/zoombie:latest
 Note that the version tag ("latest" in this example) is mandatory.
 
OPTIONS
 -h, --help
        Print help
 --insecure
        Connect to a registry which has a self-signed SSL certificate
 -p
        Prompt for password
 -u <username>
        Use the given username when authenticating with the registry
 
Password may also be set using the environment variable REGISTRY_PASSWORD
 $ export REGISTRY_PASSWORD=sesame
```

## Example
```sh
# Store password in environment variable
export REGISTRY_PASSWORD=foobar
# Delete the image mydockerregistry:5000/myrepo/zoombie:latest
./remove_image_from_registry.sh -u foo --insecure mydockerregistry:5000/myrepo/zoombie:latest
```

Note that this script will not delete the actuall blobs from the registry, only the manifests. Once you have deleted the manifests you have to manually run the garbage collector in order to delete the blobs. You do so by entring your registry container:

```sh
docker exec -ti registry_registry_1 /bin/sh
bin/registry garbage-collect /etc/docker/registry/config.yml
```

See [the documentation](https://docs.docker.com/registry/garbage-collection/) for more information about the garabe collector.



# Permissions in registry
You must have all (`["*"]`) privileges in order to delete an image, `['push']` is *not* sufficient.
However, using docker_auth you can give access per repository and image 

```yaml
### auth_config.yml
users
  "foobar":
    password: "...."
  "jane":
    password: "...."
acl:
  - match: {account: "foobar", name: "myrepo/zoombie"}
    actions: ["*"]
    comment: "foobar can do anything with image myrepo/zoombie"
  - match: {account: "jane", name: "myrepo/*"}
    actions: ["*"]
    comment: "jane can do anything with any image in the repo named myrepo"
```
