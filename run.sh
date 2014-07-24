#!/bin/bash
DB_PASS=${DB_PASS:-1q2w3e4r5t}
DB_HOST_VOLUME=${DB_HOST_VOLUME:-}
ADMIN_PASS=${ADMIN_PASS:-shipyard}
TAG=${TAG:-latest}
DEBUG=${DEBUG:-False}
DST_IP=${DST_IP":":-}
DST_PORT=${DST_PORT:-8000}
ACTION=${1:-}
if [ ! -e "/docker.sock" ] ; then
    echo "You must map your Docker socket to /docker.sock (i.e. -v /var/run/docker.sock:/docker.sock)"
    exit 2
fi

if [ -z "$ACTION" ] ; then
    echo "Usage: "
    echo "  shipyard/deploy <action>"
    echo ""
    echo "Examples: "
    echo "  docker run shipyard/deploy setup"
    echo "     Deploys Shipyard stack"
    echo "  docker run shipyard/deploy cleanup"
    echo "     Removes Shipyard stack"
    exit 1
fi

function cleanup {
    for CNT in shipyard shipyard_redis shipyard_router shipyard_db shipyard_lb
    do
        docker -H unix:///docker.sock kill $CNT > /dev/null 2>&1
        docker -H unix:///docker.sock rm $CNT > /dev/null 2>&1
    done
}

function purge {
    cleanup
    for IMG in shipyard redis router db lb
    do
        docker -H unix:///docker.sock rmi shipyard/$IMG > /dev/null 2>&1
    done
}

if [ "$ACTION" = "setup" ] ; then
    echo "
Using $TAG tag for Shipyard
This may take a moment while the Shipyard images are pulled..."
    echo "Starting Redis..."
    redis=$(docker -H unix:///docker.sock run -i -t -d --name shipyard_redis shipyard/redis)
    sleep 2
    echo "Starting App Router..."
    router=$(docker -H unix:///docker.sock run -i -t -d --link shipyard_redis:redis --name shipyard_router shipyard/router)
    sleep 2
    echo "Starting Load Balancer..."
    lb=$(docker -H unix:///docker.sock run -i -t -d --link shipyard_redis:redis --link shipyard_router:app_router --name shipyard_lb shipyard/lb)
    sleep 2
    echo "Starting DB..."
    EXTRA_DB_ARGS=""
    if [ ! -z "$DB_HOST_VOLUME" ] ; then
        EXTRA_DB_ARGS="-v $DB_HOST_VOLUME:/var/lib/postgresql"
    fi
    db=$(docker -H unix:///docker.sock run -i -t -d -e DB_NAME=shipyard -e DB_USER=shipyard -e DB_PASS=$DB_PASS $EXTRA_DB_ARGS --name shipyard_db shipyard/db)
    sleep 5
    echo "Starting Shipyard"
    shipyard=$(docker -H unix:///docker.sock run -i -t -d -p 8000:8000 --link shipyard_db:db --link shipyard_redis:redis --name shipyard -e ADMIN_PASS=$ADMIN_PASS -e DEBUG=$DEBUG --entrypoint /app/.docker/run.sh shipyard/shipyard:$TAG app master-worker)
    echo "
Shipyard Stack Deployed

You should be able to login with admin:$ADMIN_PASS at http://<docker-host-ip>:8000
You will also need to setup and register the Shipyard Agent.  See http://github.com/shipyard/shipyard-agent for details.
"
elif [ "$ACTION" = "restart" ] ; then
    echo "Restarting Shipyard Stack"
    for CNT in redis router lb db
    do
        echo "Starting $CNT"
        docker -H unix:///docker.sock start shipyard_$CNT > /dev/null
    done
    echo "Starting shipyard"
    docker -H unix:///docker.sock stop shipyard > /dev/null
    docker -H unix:///docker.sock start shipyard > /dev/null
elif [ "$ACTION" = "upgrade" ] ; then
    echo "Pulling latest Shipyard"
    docker -H unix:///docker.sock pull shipyard/shipyard

    echo "Stopping and removing existing Shipyard container"
    docker -H unix:///docker.sock kill shipyard > /dev/null
    docker -H unix:///docker.sock rm shipyard > /dev/null

    echo "Starting new Shipyard container"
    docker -H unix:///docker.sock run -i -t -d -p 8000:8000 --link shipyard_db:db --link shipyard_redis:redis --name shipyard -e DEBUG=$DEBUG --entrypoint /app/.docker/run.sh shipyard/shipyard:$TAG app master-worker > /dev/null
elif [ "$ACTION" = "cleanup" ] ; then
    cleanup
    echo "Shipyard Stack Removed"
elif [ "$ACTION" = "purge" ] ; then
    echo "Removing Shipyard images.  This could take a moment..."
    purge
fi