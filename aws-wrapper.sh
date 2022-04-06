export AWS_ACCESS_KEY_ID=<REPLACE_ME>
export AWS_SECRET_ACCESS_KEY=<REPLACE_ME>

export JUMPGATE_AGENT_RPM_URL="https://archive.cloudera.com/ccm/2.0.7/jumpgate-agent.rpm"
export METERING_AGENT_RPM_URL="https://cloudera-service-delivery-cache.s3.amazonaws.com/thunderhead-metering-heartbeat-application/clients/thunderhead-metering-heartbeat-application-0.1-SNAPSHOT.x86_64.rpm"
export FREEIPA_HEALTH_AGENT_RPM_URL="https://cloudera-service-delivery-cache.s3.amazonaws.com/freeipa-health-agent/packages/freeipa-health-agent-0.1-20210517150203gitab017e0.x86_64.rpm"
export FREEIPA_PLUGIN_RPM_URL="https://cloudera-service-delivery-cache.s3.amazonaws.com/cdp-hashed-pwd/workloads/cdp-hashed-pwd-1.0-20200319002729gitc964030.x86_64.rpm"



sh run-aws-rhel.sh --image-uuid <REPLACE_ME> --username <REPLACE_ME> --password <REPLACE_ME> 