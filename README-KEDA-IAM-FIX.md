# KEDA IAM Policy Fix for SQS Processor

## Issue
KEDA was failing to scale the SQS processor with the following error:
```
error parsing SQS queue metadata: awsAccessKeyID not found
```

This was happening because KEDA was trying to assume the role of the pod's service account but didn't have permission to do so.

## Solution
The solution was to update the IAM policy for the KEDA operator to allow it to assume the role of the pod's service account. This was done by:

1. Creating a script (`kubernetes/scripts/update-keda-policy.sh`) to update the trust policy of the pod's IAM role to allow the KEDA operator's IAM role to assume it.
2. Running the script to update the IAM policy.
3. Restarting the KEDA operator to ensure it picks up the changes.
4. Deleting and recreating the ScaledObject to apply the changes.

## Steps to Reproduce the Fix

1. Make the script executable:
```bash
chmod +x kubernetes/scripts/update-keda-policy.sh
```

2. Run the script:
```bash
./kubernetes/scripts/update-keda-policy.sh
```

3. Restart the KEDA operator:
```bash
kubectl rollout restart deployment keda-operator -n keda
```

4. Wait for the KEDA operator to be ready:
```bash
kubectl rollout status deployment keda-operator -n keda
```

5. Delete the existing ScaledObject:
```bash
kubectl delete scaledobject sqs-processor-scaler -n default
```

6. Apply the updated ScaledObject:
```bash
kubectl apply -f kubernetes/keda-service/scaled-object.yaml
```

7. Verify that the ScaledObject is ready:
```bash
kubectl get scaledobject sqs-processor-scaler -n default
```

## Configuration Details

The ScaledObject is configured to use both the `identityOwner: "pod"` setting and a TriggerAuthentication resource named `aws-pod-identity`. This tells KEDA to use the IAM role attached to the application pod's service account.

The TriggerAuthentication resource is configured to use the AWS EKS pod identity provider:
```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-pod-identity
  namespace: default
spec:
  podIdentity:
    provider: aws-eks
```

## Verification
After applying the fix, the ScaledObject shows as READY: True and there are no more error messages in the events section. The message "ScaledObject is ready for scaling" confirms that the issue has been resolved.