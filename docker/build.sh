#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

DIR=`dirname $0`
PROJECT_HOME=${DIR}/../

TIMESTAMP=$(date +%s)
BUILD_TAG="build-${TIMESTAMP}"

function cleanup {
  BUILD_IMAGE=$(docker images tinkerpop | awk "{if (\$2 == \"${BUILD_TAG}\") print \$3}")
  [ ! -z ${BUILD_IMAGE} ] && docker rmi ${BUILD_IMAGE}
  rm -f ${PROJECT_HOME}/Dockerfile
}
trap cleanup EXIT

REMOVE_CONTAINER="--rm"
[[ -n ${KEEP_CONTAINER} ]] && unset REMOVE_CONTAINER

case "$1" in
  -h | --help ) ${DIR}/scripts/build.sh -h; exit 0 ;;
esac

pushd ${PROJECT_HOME} > /dev/null

HADOOP_VERSION=$(cat pom.xml | grep -o '<hadoop.version>[^<]*' | head -n2 | cut -d '>' -f2)

docker/build-containers.sh -h "${HADOOP_VERSION}"

sed -e "s/HADOOP_VERSION\$/${HADOOP_VERSION}/" docker/build/Dockerfile.template > Dockerfile
cat >> Dockerfile <<EOF
CMD ["sh", "-c", "docker/scripts/build.sh $@"]
EOF

docker build -t tinkerpop:${BUILD_TAG} .
docker run -p 80:80 ${TINKERPOP_DOCKER_OPTS} ${REMOVE_CONTAINER} -e "JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" tinkerpop:${BUILD_TAG}

PROJECT_VERSION=$(grep tinkerpop -A2 pom.xml | grep -Po '(?<=<version>)([0-9]+\.?){3}(-SNAPSHOT)?(?=<)')
echo ${PROJECT_VERSION}
export GREMLIN_SERVER=${1:-$GREMLIN_SERVER_VERSION}
echo "GREMLIN_SERVER ${GREMLIN_SERVER}"

# build base server which is required by the docker-compose.
docker build -f ./Dockerfile --build-arg GREMLIN_SERVER_DIR=target/apache-tinkerpop-gremlin-server-${GREMLIN_SERVER}-standalone -t tinkerpop/gremlin-server:${GREMLIN_SERVER} .
#test glvs
#touch {gremlin-go,gremlin-dotnet/test,gremlin-python,gremlin-javascript}/.glv
touch gremlin-go/.glv

export ABS_PROJECT_HOME=${PROJECT_HOME}
echo "ABS_PROJECT_HOME ${ABS_PROJECT_HOME}"

if [ -z "${RUN_TESTS}" ]; then
pushd ${PROJECT_HOME}/gremlin-go > /dev/null
docker-compose up --build --exit-code-from gremlin-go-integration-tests
docker-compose down
popd > /dev/null
fi

status=$?
popd > /dev/null
exit $status
