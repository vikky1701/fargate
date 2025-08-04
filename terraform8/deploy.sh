#!/bin/bash

set -e

# Configuration
REGION="us-east-2"
ECR_REPOSITORY="607700977843.dkr.ecr.us-east-2.amazonaws.com/strapi-app-vivek"
CODEDEPLOY_APP_NAME="strapi-app-vivek"
DEPLOYMENT_GROUP_NAME="strapi-deployment-group-vivek"
TASK_DEFINITION_FAMILY="strapi-task-vivek"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_requirements() {
    print_status "Checking requirements..."
    
    for cmd in aws docker jq; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "$cmd is not installed"
            exit 1
        fi
    done
    
    print_status "All requirements satisfied"
}

# Get the latest image tag or use provided tag
get_image_tag() {
    if [ -z "$1" ]; then
        # Get the latest tag from ECR
        IMAGE_TAG=$(aws ecr describe-images \
            --region "$REGION" \
            --repository-name strapi-app-vivek \
            --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageTags[0]' \
            --output text 2>/dev/null || echo "latest")
        
        if [ "$IMAGE_TAG" = "None" ] || [ -z "$IMAGE_TAG" ]; then
            IMAGE_TAG="latest"
        fi
    else
        IMAGE_TAG="$1"
    fi
    
    print_status "Using image tag: $IMAGE_TAG"
}

# Build and push new Docker image (optional)
build_and_push() {
    if [ "${BUILD_NEW_IMAGE:-false}" = "true" ]; then
        print_status "Building new Docker image..."
        
        # Login to ECR
        aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_REPOSITORY" || {
            print_error "Failed to log in to ECR"
            exit 1
        }
        
        # Build image
        docker build -t "$ECR_REPOSITORY:$IMAGE_TAG" . || {
            print_error "Failed to build Docker image"
            exit 1
        }
        
        # Push image
        print_status "Pushing image to ECR..."
        docker push "$ECR_REPOSITORY:$IMAGE_TAG" || {
            print_error "Failed to push Docker image"
            exit 1
        }
        
        print_status "Image pushed successfully"
    fi
}

# Get current task definition
get_current_task_definition() {
    print_status "Retrieving current task definition..."
    
    aws ecs describe-task-definition \
        --region "$REGION" \
        --task-definition "$TASK_DEFINITION_FAMILY" \
        --query 'taskDefinition' > current-taskdef.json || {
        print_error "Failed to retrieve current task definition"
        exit 1
    }
}

# Create new task definition with updated image
create_new_task_definition() {
    print_status "Creating new task definition with image: $ECR_REPOSITORY:$IMAGE_TAG"
    
    # Update the image in the task definition
    jq --arg IMAGE "$ECR_REPOSITORY:$IMAGE_TAG" \
       '.containerDefinitions[0].image = $IMAGE | 
        del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)' \
       current-taskdef.json > new-taskdef.json || {
        print_error "Failed to update task definition JSON"
        exit 1
    }
    
    # Register new task definition
    NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
        --region "$REGION" \
        --cli-input-json file://new-taskdef.json \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text) || {
        print_error "Failed to register new task definition"
        exit 1
    }
    
    print_status "New task definition registered: $NEW_TASK_DEF_ARN"
}

# Create simple appspec.json for CodeDeploy
create_appspec() {
    print_status "Creating appspec.json..."
    
    # Ensure NEW_TASK_DEF_ARN is set
    if [ -z "$NEW_TASK_DEF_ARN" ]; then
        print_error "NEW_TASK_DEF_ARN is not set"
        exit 1
    fi
    
    # Create simple JSON appspec
    cat > appspec.json << EOF
{
  "version": 0.0,
  "Resources": [
    {
      "TargetService": {
        "Type": "AWS::ECS::Service",
        "Properties": {
          "TaskDefinition": "$NEW_TASK_DEF_ARN",
          "LoadBalancerInfo": {
            "ContainerName": "strapi",
            "ContainerPort": 1337
          }
        }
      }
    }
  ]
}
EOF
    
    if [ ! -f appspec.json ] || [ ! -s appspec.json ]; then
        print_error "Failed to create appspec.json"
        exit 1
    fi
    
    print_status "appspec.json content:"
    cat appspec.json
    print_status "appspec.json created successfully"
}

# Start CodeDeploy deployment
start_deployment() {
    print_status "Starting Blue-Green deployment..."

    # Check the file exists and has content
    if [ ! -f appspec.json ] || [ ! -s appspec.json ]; then
        print_error "appspec.json file is missing or empty"
        exit 1
    fi

    # Read the AppSpec content as raw string (not base64 encoded)
    APPSPEC_CONTENT=$(cat appspec.json)

    # Verify the content is not empty
    if [ -z "$APPSPEC_CONTENT" ]; then
        print_error "Failed to read appspec.json content"
        exit 1
    fi

    print_status "AppSpec content ready (${#APPSPEC_CONTENT} characters)"

    # Create deployment using JSON CLI input format
    cat > deployment-input.json << EOF
{
    "applicationName": "$CODEDEPLOY_APP_NAME",
    "deploymentGroupName": "$DEPLOYMENT_GROUP_NAME",
    "deploymentConfigName": "CodeDeployDefault.ECSCanary10Percent5Minutes",
    "revision": {
        "revisionType": "AppSpecContent",
        "appSpecContent": {
            "content": $(echo "$APPSPEC_CONTENT" | jq -R -s .)
        }
    }
}
EOF

    print_status "Deployment configuration:"
    cat deployment-input.json

    # Start deployment using the JSON file
    DEPLOYMENT_ID=$(aws deploy create-deployment \
        --region "$REGION" \
        --cli-input-json file://deployment-input.json \
        --query 'deploymentId' \
        --output text) || {
        print_error "Failed to create deployment"
        cat deployment-input.json
        exit 1
    }

    print_status "Deployment started with ID: $DEPLOYMENT_ID"
    monitor_deployment "$DEPLOYMENT_ID"
    
    # Cleanup deployment input file
    rm -f deployment-input.json
}

# Monitor deployment progress
monitor_deployment() {
    local deployment_id=$1
    print_status "Monitoring deployment progress..."
    
    while true; do
        DEPLOYMENT_STATUS=$(aws deploy get-deployment \
            --region "$REGION" \
            --deployment-id "$deployment_id" \
            --query 'deploymentInfo.status' \
            --output text 2>/dev/null) || {
            print_error "Failed to get deployment status"
            exit 1
        }
        
        case $DEPLOYMENT_STATUS in
            "Created"|"Queued"|"InProgress")
                print_status "Deployment status: $DEPLOYMENT_STATUS"
                sleep 30
                ;;
            "Succeeded")
                print_status "✅ Deployment completed successfully!"
                break
                ;;
            "Failed"|"Stopped")
                print_error "❌ Deployment failed with status: $DEPLOYMENT_STATUS"
                
                # Get failure details
                print_error "Failure details:"
                aws deploy get-deployment \
                    --region "$REGION" \
                    --deployment-id "$deployment_id" \
                    --query 'deploymentInfo.errorInformation' \
                    --output text
                exit 1
                ;;
            "")
                print_warning "Deployment status not available, retrying..."
                sleep 30
                ;;
            *)
                print_warning "Unknown deployment status: $DEPLOYMENT_STATUS"
                sleep 30
                ;;
        esac
    done
}

# Get ALB URL for testing
get_alb_url() {
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --names "strapi-alb-vivek" \
        --query 'LoadBalancers[0].DNSName' \
        --output text 2>/dev/null) || {
        print_warning "Failed to retrieve ALB DNS"
        ALB_DNS="your-alb-dns-name"
    }
    
    print_status "🌐 Application URL: http://$ALB_DNS"
}

# Cleanup temporary files
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -f current-taskdef.json new-taskdef.json appspec.json deployment-input.json
}

# Main function
main() {
    print_status "Starting Blue-Green deployment process..."
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tag)
                IMAGE_TAG="$2"
                shift 2
                ;;
            --build)
                BUILD_NEW_IMAGE="true"
                shift
                ;;
            --help)
                echo "Usage: $0 [--tag IMAGE_TAG] [--build]"
                echo "  --tag IMAGE_TAG    Use specific image tag (default: latest from ECR)"
                echo "  --build            Build and push new image before deployment"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_requirements
    get_image_tag "$IMAGE_TAG"
    build_and_push
    get_current_task_definition
    create_new_task_definition
    create_appspec
    start_deployment
    get_alb_url
    cleanup
    
    print_status "🎉 Blue-Green deployment completed successfully!"
}

# Trap to ensure cleanup on script interruption
trap 'print_error "Script interrupted"; cleanup; exit 1' INT TERM

# Run main function
main "$@"