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

function usage {
  echo -e "\nUsage: `basename $0` [OPTIONS]" \
          "\nBuild the current local TinkerPop project in a Docker container." \
          "\n\nOptions are:\n" \
          "\n\t-t,  --tests              run standard test suite for modules except non-Java GLVs" \
          "\n\t-i,  --integration-tests  run integration tests for modules except non-Java GLVs" \
          "\n\t-a,  --all                run tests for all non-Java GLVs and gremlin-console" \
          "\n\t-go, --golang             run tests for Go GLV" \
          "\n\t-py, --python             run tests for Python GLV" \
          "\n\t-dn, --dotnet             run tests for Dotnet GLV" \
          "\n\t-js, --javascript         run tests for JavaScript GLV" \
          "\n\t-c,  --console            run tests for gremlin-console" \
          "\n\t-j,  --java-docs          build Java docs" \
          "\n\t-d,  --docs               build user docs" \
          "\n\t-h,  --help               show this message" \
          "\n"
}

ARGS=""
INCLUDE_GO=""
INCLUDE_PYTHON=""
INCLUDE_DOTNET=""
INCLUDE_JAVASCRIPT=""
INCLUDE_CONSOLE=""
while [ ! -z "$1" ]; do
  case "$1" in
    -t  | --tests ) ARGS="${ARGS} -t"; shift ;;
    -i  | --integration-tests ) ARGS="${ARGS} -i"; shift ;;
    -a  | --all ) INCLUDE_GO=true; INCLUDE_PYTHON=true; INCLUDE_DOTNET=true; INCLUDE_JAVASCRIPT=true; INCLUDE_CONSOLE=true; shift ;;
    -go | --golang ) INCLUDE_GO=true; shift ;;
    -py | --python ) INCLUDE_PYTHON=true; shift ;;
    -dn | --dotnet ) INCLUDE_DOTNET=true; shift ;;
    -js | --javascript ) INCLUDE_JAVASCRIPT=true; shift ;;
    -c  | --console ) INCLUDE_CONSOLE=true; shift ;;
    -j  | --java-docs ) ARGS="${ARGS} -j"; shift ;;
    -d  | --docs ) ARGS="${ARGS} -d"; shift ;;
    -h  | --help ) usage; exit 0 ;;
    *) usage 1>&2; exit 1 ;;
  esac
done

pushd ${PROJECT_HOME} > /dev/null
ABS_PROJECT_HOME=$(pwd) # absolute path required by some Docker variables.
echo "ABS_PROJECT_HOME ${ABS_PROJECT_HOME}"

HADOOP_VERSION=$(cat pom.xml | grep -o '<hadoop.version>[^<]*' | head -n2 | cut -d '>' -f2)

docker/build-containers.sh -h "${HADOOP_VERSION}"

sed -e "s/HADOOP_VERSION\$/${HADOOP_VERSION}/" docker/build/Dockerfile.template > Dockerfile
cat >> Dockerfile <<EOF
CMD ["sh", "-c", "docker/scripts/build.sh ${ARGS}"]
EOF

# GREMLIN_SERVER is the project version e.g. 3.5.5-SNAPSHOT
GREMLIN_SERVER=$(grep tinkerpop -A2 pom.xml | grep -Po '(?<=<version>)([0-9]+\.?){3}(-SNAPSHOT)?(?=<)')
echo "GREMLIN_SERVER ${GREMLIN_SERVER}"

docker build -t tinkerpop:${BUILD_TAG} .
docker run -p 80:80 ${TINKERPOP_DOCKER_OPTS} ${REMOVE_CONTAINER} \
           -e "JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" \
           --mount type=bind,src=$(pwd)/gremlin-server/,dst=/usr/src/tinkerpop/gremlin-server/ \
           --mount type=bind,src=$(pwd)/gremlin-test/,dst=/usr/src/tinkerpop/gremlin-test/ \
           --mount type=bind,src=$(pwd)/gremlin-console/,dst=/usr/src/tinkerpop/gremlin-console/ \
           --mount type=bind,src=$(pwd)/neo4j-gremlin/,dst=/usr/src/tinkerpop/neo4j-gremlin/ \
           tinkerpop:${BUILD_TAG}

# build base server which is required by the docker-compose.
pushd ${ABS_PROJECT_HOME}/gremlin-server > /dev/null
docker build -f ./Dockerfile --build-arg GREMLIN_SERVER_DIR=target/apache-tinkerpop-gremlin-server-${GREMLIN_SERVER}-standalone -t tinkerpop/gremlin-server:${GREMLIN_SERVER} .
popd > /dev/null

if [ -n "${INCLUDE_GO}" ]; then
pushd ${ABS_PROJECT_HOME}/gremlin-go > /dev/null
docker-compose up --build --exit-code-from gremlin-go-integration-tests
docker-compose down
popd > /dev/null
fi

if [ -n "${INCLUDE_PYTHON}" ]; then
pushd ${ABS_PROJECT_HOME}/gremlin-python > /dev/null
docker-compose up --build --abort-on-container-exit gremlin-server-test-python gremlin-python-integration-tests
docker-compose down
popd > /dev/null
fi

if [ -n "${INCLUDE_DOTNET}" ]; then
pushd ${ABS_PROJECT_HOME}/gremlin-dotnet/test > /dev/null
docker-compose up --build --exit-code-from gremlin-dotnet-integration-tests
docker-compose down
popd > /dev/null
fi

if [ -n "${INCLUDE_JAVASCRIPT}" ]; then
pushd ${ABS_PROJECT_HOME}/gremlin-javascript/src/main/javascript/gremlin-javascript > /dev/null
docker-compose up --build --exit-code-from gremlin-js-integration-tests
docker-compose down
popd > /dev/null
fi

if [ -n "${INCLUDE_CONSOLE}" ]; then
pushd ${ABS_PROJECT_HOME}/gremlin-console > /dev/null
docker build -t gremlin-console-test:py3.8jre11 ./src/test/python/docker
docker run --rm \
           --mount type=bind,src=$(pwd)/src/test/python,dst=/console_app \
           --mount type=bind,src=$(pwd)/target/apache-tinkerpop-gremlin-console-${GREMLIN_SERVER}-standalone,dst=/console_app/gremlin-console \
           gremlin-console-test:py3.8jre11
popd > /dev/null
fi

status=$?
popd > /dev/null
exit $status
