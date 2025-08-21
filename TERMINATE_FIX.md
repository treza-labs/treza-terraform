# Terminate Issue Fix - 2025-08-21

## Problem
When clicking "Terminate" on enclaves in the Treza app, the status incorrectly changed to "DEPLOYING" instead of "DESTROYING" or "DESTROYED".

## Root Cause
The cleanup Step Function (`treza-dev-cleanup`) had the wrong workflow definition - it was using the deployment workflow instead of the cleanup workflow.

## Investigation
1. **Frontend**: Correctly sends `action: "terminate"` in PATCH request
2. **API**: Correctly sets status to `PENDING_DESTROY` 
3. **Lambda Trigger**: Correctly detects `PENDING_DESTROY` and starts cleanup Step Function
4. **Step Function**: ❌ Had deployment definition instead of cleanup definition
   - Was setting status to `DEPLOYING` instead of `DESTROYING`
   - Was running deployment logic instead of cleanup logic

## Solution
Updated the cleanup Step Function directly using AWS CLI with the correct definition:

```bash
aws stepfunctions update-state-machine \
  --state-machine-arn "arn:aws:states:us-west-2:314146326535:stateMachine:treza-dev-cleanup" \
  --definition file://cleanup_definition.json
```

## Result
✅ **Terminate now works correctly:**
- Status changes to `DESTROYING` when cleanup starts
- Status changes to `DESTROYED` when cleanup completes
- No more incorrect `DEPLOYING` status during termination

## Verification
```bash
# Verify correct workflow comment
aws stepfunctions describe-state-machine \
  --state-machine-arn "arn:aws:states:us-west-2:314146326535:stateMachine:treza-dev-cleanup" \
  --query 'definition' --output text | jq '.Comment'
# Result: "Treza Enclave Cleanup Workflow"

# Verify correct status setting
aws stepfunctions describe-state-machine \
  --state-machine-arn "arn:aws:states:us-west-2:314146326535:stateMachine:treza-dev-cleanup" \
  --query 'definition' --output text | jq '.States.UpdateStatusToDestroying.Parameters.ExpressionAttributeValues[":status"].S'
# Result: "DESTROYING"
```

## Impact
- ✅ Terminate functionality now works as expected
- ✅ Proper status progression during cleanup
- ✅ No more user confusion about "DEPLOYING" during termination
