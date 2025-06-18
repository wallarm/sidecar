# This file used for import in other files

RED='\033[0;31m'
NC='\033[0m'

function check_mandatory_vars() {

    declare -a mandatory
    declare -a allure_mandatory

    mandatory=(
      WALLARM_API_TOKEN
      WALLARM_API_HOST
      WALLARM_API_PRESET
      CLIENT_ID
      USER_TOKEN
      WEBHOOK_API_KEY
      WEBHOOK_UUID
      SMOKE_REGISTRY_TOKEN
      SMOKE_REGISTRY_SECRET
      NODE_GROUP_NAME
    )

    env_list=""

    for var in "${mandatory[@]}"; do
      if [[ -z "${!var:-}" ]]; then
        env_list+=" $var"
      fi
    done

    if [[ "${ALLURE_UPLOAD_REPORT:-false}" == "true" ]]; then
      allure_mandatory=(
        ALLURE_TOKEN
        ALLURE_ENVIRONMENT_ARCH
        ALLURE_PROJECT_ID
        ALLURE_GENERATE_REPORT
        ALLURE_ENVIRONMENT_K8S
      )

      for var in "${allure_mandatory[@]}"; do
        if [[ -z "${!var:-}" ]]; then
          env_list+=" $var"
        fi
      done
    fi

    if [[ -n "$env_list" ]]; then
      for var in ${env_list}; do
        echo -e "${RED}Environment variable $var must be set${NC}"
      done
      exit 1
    fi

}

function cleanup() {
  if [[ "${KUBETEST_IN_DOCKER:-}" == "true" ]]; then
    kind "export" logs --name ${KIND_CLUSTER_NAME} "${ARTIFACTS}/logs" || true
  fi
  if [[ "${CI:-}" == "true" ]]; then
    kind delete cluster \
      --verbosity=${KIND_LOG_LEVEL} \
      --name ${KIND_CLUSTER_NAME}
  fi
}

function get_controller_logs_and_fail() {
    echo "#################################"
    echo "######## Controller logs ########"
    echo "#################################"
    kubectl logs -l "app.kubernetes.io/component=controller" --tail=-1 || true
    echo -e "#################################\n"

    echo "#####################################"
    echo "######## Post-analytics logs ########"
    echo -e "#####################################\n"
    for CONTAINER in appstructure supervisord wstore ; do
      echo "#######################################"
      echo "###### ${CONTAINER} container logs ######"
      echo -e "#######################################\n"
      kubectl logs -l "app.kubernetes.io/component=postanalytics" -c ${CONTAINER} --tail=-1 || true
      echo -e "#######################################\n"
    done

    for COMPONENT in controller postanalytics ; do
          echo "#######################################"
          echo "###### Describe ${COMPONENT} pod ######"
          echo -e "#######################################\n"
          kubectl describe po -l "app.kubernetes.io/component=${COMPONENT}"
          echo -e "#######################################\n"
    done

    exit 1
}

###

function get_logs_and_fail() {
    get_logs
    extra_debug_logs
    clean_allure_report
    exit 1
}

function get_logs() {
    echo "#################################"
    echo "######## Controller logs ########"
    echo "#################################"
    kubectl logs -l "app.kubernetes.io/component=controller" --tail=-1
    echo -e "#################################\n"

    echo "#################################"
    echo "######## Post-analytics Pod #####"
    echo "#################################"
    for CONTAINER in appstructure supervisord wstore ; do
      echo "#######################################"
      echo "###### ${CONTAINER} container logs ######"
      echo -e "#######################################\n"
      kubectl logs -l "app.kubernetes.io/component=postanalytics" -c ${CONTAINER} --tail=-1
      echo -e "#######################################\n"
    done

    echo "#################################"
    echo "######## Application Pod ########"
    echo -e "#################################\n"

    echo "####################################################"
    echo "###### List directory /opt/wallarm/etc/wallarm #####"
    echo "####################################################"
    kubectl exec "${POD}" -c sidecar-proxy -- sh -c "ls -laht /opt/wallarm/etc/wallarm && cat /opt/wallarm/etc/wallarm/node.yaml" || true
    echo -e "#####################################################\n"

    echo "############################################"
    echo "###### List directory /var/lib/nginx/wallarm"
    echo "############################################"
    kubectl exec "${POD}" -c sidecar-proxy -- sh -c "ls -laht /opt/wallarm/var/lib/nginx/wallarm && ls -laht /opt/wallarm/var/lib/nginx/wallarm/shm" || true
    echo -e "############################################\n"

    echo "############################################################"
    echo "###### List directory /opt/wallarm/var/lib/wallarm-acl #####"
    echo "############################################################"
    kubectl exec "${POD}" -c sidecar-proxy -- sh -c "ls -laht /opt/wallarm/var/lib/wallarm-acl" || true
    echo -e "############################################################\n"

    echo "#################################"
    echo "######## Application Pod Logs ###"
    echo -e "#################################\n"
    kubectl logs -l "wallarm-sidecar=enabled" --all-containers --ignore-errors --since=1h
    echo -e "#################################\n"
}

function extra_debug_logs {
  echo "############################################"
  echo "###### Extra cluster debug info ############"
  echo "############################################"

  echo "Grepping cluster OOMKilled events..."
  kubectl get events -A | grep -i OOMKill || true

  echo "Displaying pods state in default namespace..."
  kubectl get pods

}

function clean_allure_report() {
  [[ "$ALLURE_GENERATE_REPORT" == false && -d "allure_report" ]] && rm -rf allure_report/* 2>/dev/null || true
}
