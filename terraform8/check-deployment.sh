#!/bin/bash

# Configuration
REGION="us-east-2"
CODEDEPLOY_APP_NAME="strapi-app-vivek"
DEPLOYMENT_GROUP_NAME="strapi-deployment-group-vivek"
CLUSTER_NAME="strapi-cluster-vivek"
SERVICE_NAME="strapi-service-vivek"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check ECS Service Status
check_ecs_service() {
    print_header "ECS Service Status"
    
    SERVICE_INFO=$(aws ecs describe-services \
        --region $REGION \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME \
        --query 'services[0]')
    
    RUNNING_COUNT=$(echo $SERVICE_INFO | jq -r '.runningCount')
    DESIRED_COUNT=$(echo $SERVICE_INFO | jq -r '.desiredCount')
    TASK_DEFINITION=$(echo $SERVICE_INFO | jq -r '.taskDefinition' | sed 's/.*\///')
    
    echo "Service: $SERVICE_NAME"
    echo "Running Tasks: $RUNNING_COUNT/$DESIRED_COUNT"
    echo "Current Task Definition: $TASK_DEFINITION"
    
    if [ "$RUNNING_COUNT" -eq "$DESIRED_COUNT" ]; then
        print_status "✅ Service is healthy"
    else
        print_warning "⚠️  Service is not at desired capacity"
    fi
}

# Check Target Group Health
check_target_groups() {
    print_header "Target Group Health"
    
    # Get target groups
    TARGET_GROUPS=$(aws elbv2 describe-target-groups \
        --region $REGION \
        --names "strapi-blue-tg-vivek" "strapi-green-tg-vivek" \
        --query 'TargetGroups[*].[TargetGroupName,TargetGroupArn]' \
        --output text)
    
    while IFS=$'\t' read -r TG_NAME TG_ARN; do
        echo "Target Group: $TG_NAME"
        
        # Get target health
        HEALTH_STATUS=$(aws elbv2 describe-target-health \
            --region $REGION \
            --target-group-arn $TG_ARN \
            --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]' \
            --output text)
        
        if [ -z "$HEALTH_STATUS" ]; then
            echo "  No targets registered"
        else
            while IFS=$'\t' read -r TARGET_ID HEALTH_STATE; do
                case $HEALTH_STATE in
                    "healthy")
                        print_status "  ✅ $TARGET_ID: $HEALTH_STATE"
                        ;;
                    "unhealthy")
                        print_error "  ❌ $TARGET_ID: $HEALTH_STATE"
                        ;;
                    *)
                        print_warning "  ⏳ $TARGET_ID: $HEALTH_STATE"
                        ;;
                esac
            done <<< "$HEALTH_STATUS"
        fi
        echo
    done <<< "$TARGET_GROUPS"
}

# Check Recent Deployments
check_recent_deployments() {
    print_header "Recent Deployments"
    
    DEPLOYMENTS=$(aws deploy list-deployments \
        --region $REGION \
        --application-name $CODEDEPLOY_APP_NAME \
        --deployment-group-name $DEPLOYMENT_GROUP_NAME \
        --max-items 5 \
        --query 'deployments' \
        --output text)
    
    if [ -z "$DEPLOYMENTS" ]; then
        echo "No deployments found"
        return
    fi
    
    for DEPLOYMENT_ID in $DEPLOYMENTS; do
        DEPLOYMENT_INFO=$(aws deploy get-deployment \
            --region $REGION \
            --deployment-id $DEPLOYMENT_ID \
            --query 'deploymentInfo.[status,createTime,completeTime]' \
            --output text)
        
        STATUS=$(echo $DEPLOYMENT_INFO | cut -f1)
        CREATE_TIME=$(echo $DEPLOYMENT_INFO | cut -f2)
        COMPLETE_TIME=$(echo $DEPLOYMENT_INFO | cut -f3)
        
        case $STATUS in
            "Succeeded")
                print_status "✅ $DEPLOYMENT_ID: $STATUS (Created: $CREATE_TIME)"
                ;;
            "Failed"|"Stopped")
                print_error "❌ $DEPLOYMENT_ID: $STATUS (Created: $CREATE_TIME)"
                ;;
            "InProgress"|"Created"|"Queued")
                print_warning "⏳ $DEPLOYMENT_ID: $STATUS (Created: $CREATE_TIME)"
                ;;
            *)
                echo "🔄 $DEPLOYMENT_ID: $STATUS (Created: $CREATE_TIME)"
                ;;
        esac
    done
}

# Check ALB Status
check_alb_status() {
    print_header "Application Load Balancer"
    
    ALB_INFO=$(aws elbv2 describe-load-balancers \
        --region $REGION \
        --names "strapi-alb-vivek" \
        --query 'LoadBalancers[0].[DNSName,State.Code]' \
        --output text)
    
    DNS_NAME=$(echo $ALB_INFO | cut -f1)
    STATE=$(echo $ALB_INFO | cut -f2)
    
    echo "DNS Name: $DNS_NAME"
    echo "State: $STATE"
    
    if [ "$STATE" = "active" ]; then
        print_status "✅ Load balancer is active"
        echo
        print_status "🌐 Main URL: http://$DNS_NAME"
        print_status "🧪 Test URL: http://$DNS_NAME:8080"
    else
        print_warning "⚠️  Load balancer state: $STATE"
    fi
}

# Check Application Health
check_app_health() {
    print_header "Application Health Check"
    
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --region $REGION \
        --names "strapi-alb-vivek" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    echo "Testing main application..."
    if curl -sf "http://$ALB_DNS" > /dev/null 2>&1; then
        print_status "✅ Main application is responding"
    else
        print_error "❌ Main application is not responding"
    fi
    
    echo "Testing Green/Test environment..."
    if curl -sf "http://$ALB_DNS:8080" > /dev/null 2>&1; then
        print_status "✅ Test environment is responding"
    else
        print_warning "⚠️  Test environment is not responding (this is normal if no Green deployment is active)"
    fi
}

# Main function
main() {
    echo -e "${BLUE}Strapi Blue-Green Deployment Status Check${NC}"
    echo "$(date)"
    echo
    
    check_ecs_service
    echo
    check_target_groups
    echo
    check_recent_deployments
    echo
    check_alb_status
    echo
    check_app_health
    
    echo
    print_status "Status check completed!"
}

# Check if specific deployment ID is provided
if [ "$1" ]; then
    print_header "Specific Deployment Status"
    
    DEPLOYMENT_INFO=$(aws deploy get-deployment \
        --region $REGION \
        --deployment-id $1 \
        --query 'deploymentInfo')
    
    echo $DEPLOYMENT_INFO | jq .
else
    main
fi