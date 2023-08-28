import os
import subprocess
import pytest
import requests
import logging
import shlex
import sysconfig
from time import sleep

logger = logging.getLogger(__name__)

ALLOWED_HTTP_PATH = '/get'
FORBIDDEN_HTTP_PATH = '/?id=\'or+1=1--a-<script>prompt(1)</script>\''
SCRIPT_PATH = os.path.dirname(os.path.realpath(__file__))
PATCHES_PATH = f'{SCRIPT_PATH}/kustomize/patches'
WAIT_PODS_TIMEOUT = '120s'

print('PATCHES_PATH: ${PATCHES_PATH}')
patchList = []
for patchPath in os.listdir(PATCHES_PATH):
    patchList.append(patchPath)


class Helpers:
    @staticmethod
    def subprocess_run(cmd: str) -> subprocess.CompletedProcess:
        logger.info(f'Command: {cmd}')
        completed_process = subprocess.run(shlex.split(cmd), capture_output=True, text=True)
        if completed_process.returncode != 0:
            logger.error(completed_process.stderr)
            raise Exception(f'Command: {cmd} '
                            f'Exit code: {completed_process.returncode} '
                            f'Stderr: {completed_process.stderr}')
        return completed_process

    @staticmethod
    def create_namespace(namespace: str) -> None:
        cmd = f'kubectl create namespace {namespace}'
        logger.info('Create namespace ...')
        Helpers.subprocess_run(cmd)

    @staticmethod
    def create_resources(path: str, namespace: str) -> None:
        cmd = f'kubectl --namespace {namespace} create -k {path}/'
        logger.info('Create resources ...')
        Helpers.subprocess_run(cmd)

    @staticmethod
    def wait_pods(namespace: str) -> None:
        # Need delay here because in some cases we have error: no matching resources found
        sleep(2)
        cmd = f'kubectl --namespace {namespace} ' \
              f'wait --for=condition=Ready pods --all --timeout={WAIT_PODS_TIMEOUT}'
        logger.info('Wait for all Pods ready ...')
        Helpers.subprocess_run(cmd)

    @staticmethod
    def delete_namespace(namespace: str) -> None:
        cmd = f'kubectl delete namespace {namespace} --ignore-not-found'
        logger.info('Delete namespace ...')
        Helpers.subprocess_run(cmd)

    @staticmethod
    def setup_resources(path: str, namespace: str) -> None:
        Helpers.create_namespace(namespace)
        Helpers.create_resources(path, namespace)
        Helpers.wait_pods(namespace)


@pytest.fixture(scope="function")
def helpers():
    return Helpers


@pytest.fixture(scope="function")
def teardown_namespace():
    config = {}
    yield config
    namespace = config['namespace']
    logger.info(f'Teardown namespace {namespace} ...')
    Helpers.delete_namespace(namespace)


class Tests:
    @pytest.mark.parametrize("config", patchList)
    def test_main_functionality(self, config, helpers, teardown_namespace):
        config_path = f'{PATCHES_PATH}/{config}'
        namespace = config.replace('_', '-')
        base_url = f'http://dummy-app-svc.{namespace}.svc'
        allowed_url = base_url + ALLOWED_HTTP_PATH
        forbidden_url = base_url + FORBIDDEN_HTTP_PATH

        # Register teardown and setup resources for test
        teardown_namespace['namespace'] = namespace

        # Skip tests with ip-tables if run on arm64
        if ("iptables_enabled" in config) and ("aarch64" in sysconfig.get_platform().split("-")[-1].lower()):
            pytest.skip(f'Skip {config} test since aarch64')
            return

        helpers.setup_resources(config_path, namespace)

        # Need delay here to ensure that service is ready to send traffic to pods
        sleep(2)

        logger.info(f'Performing allowed request: {allowed_url} ...')
        allowed_request = requests.get(allowed_url)
        assert allowed_request.status_code == 200

        logger.info(f'Performing forbidden request: {forbidden_url} ...')
        forbidden_request = requests.get(forbidden_url)
        assert forbidden_request.status_code == 403
