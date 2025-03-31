#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to list all pods
list_pods() {
  echo -e "\n${BLUE}=== Available Pods ===${NC}"
  kubectl get pods
}

# Function to select a pod interactively
select_pod() {
  list_pods
  
  # Ask user to enter pod name or pattern
  echo -e "\n${YELLOW}Enter pod name (or part of name) to monitor (or 'all' for all pods):${NC}"
  read pod_pattern
  
  # Check if user wants to monitor all pods
  if [ "$pod_pattern" = "all" ]; then
    selected_pod="all"
    return 0
  fi
  
  # Find pods matching the pattern
  matching_pods=$(kubectl get pods | grep -i "$pod_pattern" | awk '{print $1}')
  pod_count=$(echo "$matching_pods" | grep -v "^$" | wc -l)
  
  if [ "$pod_count" -eq 0 ]; then
    echo -e "${RED}No pods match '$pod_pattern'. Please try again.${NC}"
    return 1
  elif [ "$pod_count" -eq 1 ]; then
    # Only one match, use it directly
    selected_pod=$(echo "$matching_pods" | head -n 1)
    return 0
  else
    # Multiple matches, let user choose
    echo -e "\n${YELLOW}Multiple pods match your pattern. Please select one:${NC}"
    select selected_pod in $matching_pods; do
      if [ -n "$selected_pod" ]; then
        return 0
      else
        echo -e "${RED}Invalid selection. Please try again.${NC}"
      fi
    done
  fi
}

# Function to monitor logs for all pods
monitor_all_pods() {
  echo -e "\n${BLUE}=== Starting real-time log monitoring for ALL pods ===${NC}"
  echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}\n"
  
  # Get all pod names
  all_pods=$(kubectl get pods -o name | cut -d'/' -f2)
  
  # Check if we have pods
  if [ -z "$all_pods" ]; then
    echo -e "${RED}No pods found in the current namespace.${NC}"
    return
  fi
  
  # Use a temporary file for log output
  temp_log_file=$(mktemp)
  
  # Start monitoring each pod in the background, all output goes to the temp file
  for pod in $all_pods; do
    kubectl logs -f "$pod" --timestamps | sed "s/^/[$pod] /" >> "$temp_log_file" 2>&1 &
  done
  
  # Store all background PIDs
  pids=$(jobs -p)
  
  # Display the combined logs in real-time
  tail -f "$temp_log_file" &
  tail_pid=$!
  
  # Wait for user to press Ctrl+C
  trap "kill $tail_pid $pids 2>/dev/null; rm -f $temp_log_file; echo -e '\n${BLUE}Monitoring stopped.${NC}'; trap - INT; return" INT
  wait $tail_pid
}

# Function to monitor logs
monitor_logs() {
  local pod=$1
  local option=$2
  
  # If monitoring all pods
  if [ "$pod" = "all" ]; then
    monitor_all_pods
    return
  fi
  
  echo -e "\n${BLUE}=== Starting real-time log monitoring for pod: $pod ===${NC}"
  echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}\n"
  
  case $option in
    1) # Standard logs
      kubectl logs -f "$pod"
      ;;
    2) # Logs with timestamps
      kubectl logs -f --timestamps "$pod"
      ;;
    3) # Filter INFO logs
      kubectl logs -f "$pod" | grep --color=always "INFO"
      ;;
    4) # Filter WARNING logs
      kubectl logs -f "$pod" | grep --color=always "WARN\|WARNING"
      ;;
    5) # Filter ERROR logs
      kubectl logs -f "$pod" | grep --color=always "ERROR\|Exception\|FATAL"
      ;;
    *) # Default to standard logs
      kubectl logs -f "$pod"
      ;;
  esac
}

# Main execution starts here
clear
echo -e "${BLUE}=== Kubernetes Real-time Pod Monitor ===${NC}"

while true; do
  # Select pod to monitor
  if ! select_pod; then
    continue
  fi
  
  # Show monitoring options
  echo -e "\n${BLUE}=== Monitoring Options for pod: $selected_pod ===${NC}"
  
  if [ "$selected_pod" = "all" ]; then
    # When all pods are selected, only show the timestamps option
    echo -e "${GREEN}1${NC}) Monitor all pods with timestamps"
    echo -e "${GREEN}q${NC}) Quit"
    
    # Get user's choice
    echo -e "\n${YELLOW}Select an option:${NC}"
    read choice
    
    if [ "$choice" = "q" ]; then
      echo -e "\n${BLUE}Exiting. Goodbye!${NC}"
      exit 0
    elif [ "$choice" = "1" ]; then
      monitor_logs "all" 2
    else
      echo -e "${RED}Invalid option. Please try again.${NC}"
      continue
    fi
  else
    # Regular options for a specific pod
    echo -e "${GREEN}1${NC}) Standard logs"
    echo -e "${GREEN}2${NC}) Logs with timestamps"
    echo -e "${GREEN}3${NC}) Only INFO logs"
    echo -e "${GREEN}4${NC}) Only WARNING logs"
    echo -e "${GREEN}5${NC}) Only ERROR/Exception logs"
    echo -e "${GREEN}q${NC}) Quit"
    
    # Get user's choice
    echo -e "\n${YELLOW}Select an option:${NC}"
    read choice
    
    # Process user's choice
    if [ "$choice" = "q" ]; then
      echo -e "\n${BLUE}Exiting. Goodbye!${NC}"
      exit 0
    elif [[ "$choice" =~ ^[1-5]$ ]]; then
      monitor_logs "$selected_pod" "$choice"
    else
      echo -e "${RED}Invalid option. Please try again.${NC}"
      continue
    fi
  fi
  
  # After monitoring is stopped with Ctrl+C
  echo -e "\n${BLUE}Monitoring stopped.${NC}"
  echo -e "\n${YELLOW}What would you like to do next?${NC}"
  echo -e "${GREEN}1${NC}) Monitor the same pod again"
  echo -e "${GREEN}2${NC}) Select a different pod"
  echo -e "${GREEN}q${NC}) Quit"
  read next_action
  
  case $next_action in
    1) continue ;;
    2) clear; continue ;;
    *) echo -e "\n${BLUE}Exiting. Goodbye!${NC}"; exit 0 ;;
  esac
done