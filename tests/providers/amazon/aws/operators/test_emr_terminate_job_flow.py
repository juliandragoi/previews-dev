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
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from airflow.exceptions import TaskDeferred
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.providers.amazon.aws.operators.emr import EmrTerminateJobFlowOperator
from airflow.providers.amazon.aws.triggers.emr import EmrTerminateJobFlowTrigger

TERMINATE_SUCCESS_RETURN = {"ResponseMetadata": {"HTTPStatusCode": 200}}


class TestEmrTerminateJobFlowOperator:
    def setup_method(self):
        # Mock out the emr_client (moto has incorrect response)
        mock_emr_client = MagicMock()
        mock_emr_client.terminate_job_flows.return_value = TERMINATE_SUCCESS_RETURN

        mock_emr_session = MagicMock()
        mock_emr_session.client.return_value = mock_emr_client

        # Mock out the emr_client creator
        self.boto3_session_mock = MagicMock(return_value=mock_emr_session)

    @patch.object(S3Hook, "parse_s3_url", return_value="valid_uri")
    def test_execute_terminates_the_job_flow_and_does_not_error(self, _):
        with patch("boto3.session.Session", self.boto3_session_mock), patch(
            "airflow.providers.amazon.aws.hooks.base_aws.isinstance"
        ) as mock_isinstance:
            mock_isinstance.return_value = True
            operator = EmrTerminateJobFlowOperator(
                task_id="test_task", job_flow_id="j-8989898989", aws_conn_id="aws_default"
            )

            operator.execute(MagicMock())

    @patch.object(S3Hook, "parse_s3_url", return_value="valid_uri")
    def test_create_job_flow_deferrable(self, _):
        with patch("boto3.session.Session", self.boto3_session_mock), patch(
            "airflow.providers.amazon.aws.hooks.base_aws.isinstance"
        ) as mock_isinstance:
            mock_isinstance.return_value = True
            operator = EmrTerminateJobFlowOperator(
                task_id="test_task",
                job_flow_id="j-8989898989",
                aws_conn_id="aws_default",
                deferrable=True,
            )
            with pytest.raises(TaskDeferred) as exc:
                operator.execute(MagicMock())

        assert isinstance(
            exc.value.trigger, EmrTerminateJobFlowTrigger
        ), "Trigger is not a EmrTerminateJobFlowTrigger"
