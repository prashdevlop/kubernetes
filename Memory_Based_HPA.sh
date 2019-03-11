
#!/bin/bash

podmem=0
totalpodmem=0
sumoftotalmem=0
TODAY=`date +%F`
KUBECTL=/usr/bin/kubectl
SCRIPT_HOME=/var/log/kube-deploy
if [ ! -d $SCRIPT_HOME ]; then
  mkdir -p $SCRIPT_HOME
fi
#LOG_FILE=$SCRIPT_HOME/kube-$TODAY.log
#touch $LOG_FILE
RED='\033[01;31m'
YELLOW='\033[0;33m'
NONE='\033[00m'

print_help(){
  echo -e "${YELLOW}Use the following Command:"
  echo -e "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  echo -e "${RED}./<script-name> --action <action-name> --deployment <deployment-name> --scaleup <scaleupthreshold> --scaledown <scaledownthreshold>"
  echo -e "${YELLOW}+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  printf "Choose one of the available actions below:\n"
  printf " get-podmemory\n deploy-pod-autoscaling\n"
  echo -e "You can get the list of existing deployments using command: kubectl get deployments${NONE}"
}
ARG="$#"
if [[ $ARG -eq 0 ]]; then
  print_help
  exit
fi

while test -n "$1"; do
   case "$1" in
        --action)
            ACTION=$2
            shift
            ;;
        --deployment)
            DEPLOYMENT=$2
            shift
            ;;
        --scaleup)
            SCALEUPTHRESHOLD=$2
            shift
            ;;
        --scaledown)
            SCALEDOWNTHRESHOLD=$2
            shift
            ;;
       *)
            print_help
            exit
            ;;
   esac
    shift
done

echo "########################################"
echo "Running  "$ACTION"  for  "$DEPLOYMENT
echo "########################################"

LOG_FILE=$SCRIPT_HOME/kube-$DEPLOYMENT-$TODAY.log
touch $LOG_FILE

REPLICAS=`$KUBECTL get deployments --all-namespaces | grep $DEPLOYMENT | awk -F " " '{print $3}'`


##########################################
#defining function to calculate pod memory

calculate_podmemory(){


pods=`$KUBECTL top pods --all-namespaces | grep $DEPLOYMENT | awk '{print $2}'`


for i in $pods
do
echo "==========================="
echo "calculating podmemory for $i"
echo "==========================="
namespace=`$KUBECTL top pods --all-namespaces | grep $i | awk '{print $1}'`
TOTALMEM=`$KUBECTL describe pods $DEPLOYMENT -n $namespace| grep -A 2 "Limits:" | grep memory | grep -o '[0-9]\+[A-Z]' | head -1`

if [[ $TOTALMEM =~ .*G.* ]]; then
    TOTALMEMINGB=${TOTALMEM//[!0-9]/}
    TOTALMEMINMB=$((TOTALMEMINGB * 1024))
    echo "Total Pod Memory Allocated: "$TOTALMEMINMB"MB"
	sumoftotalmem=$((sumoftotalmem+TOTALMEMINMB))
     
elif [[ $TOTALMEM =~ .*M.* ]]; then
    TOTALMEMINMB=${TOTALMEM//[!0-9]/}
    echo "Total Pod Memory Allocated: "$TOTALMEMINMB"MB" 
	sumoftotalmem=$((sumoftotalmem+TOTALMEMINMB))
     
fi
podmem=`$KUBECTL top pod --all-namespaces | grep $i | awk '{print $4}' | grep -o '[0-9]\+'`
echo "Used Pod Memory: "$podmem"MB"
totalpodmem=$((podmem+totalpodmem))
UTILIZEDPODMEM=$(awk "BEGIN { pc=100*${podmem}/${TOTALMEMINMB}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
echo "Pod memory Percent: "$UTILIZEDPODMEM"%" 
done

#podmem=`$KUBECTL top pod --all-namespaces | grep $DEPLOYMENT | awk '{print $3}' | grep -o '[0-9]\+'`

AVGPODMEM=$(( $totalpodmem/$REPLICAS ))
avgoftotalmem=$(( $sumoftotalmem/$REPLICAS ))

echo "==========================="
echo "Average Pod Memory: "$AVGPODMEM"MB"
AVGPODMEMPER=$(awk "BEGIN { pc=100*${AVGPODMEM}/${avgoftotalmem}; i=int(pc); print (pc-i<0.5)?i:i+1 }")
echo "Average Pod memory Percent: "$AVGPODMEMPER"%"
echo "==========================="

}

##########################################
#defining function to autoscale based on pod memory

podmemory_autoscale(){
  if [ $AVGPODMEMPER -gt $SCALEUPTHRESHOLD ]
  then
    echo "Memory is greater than threshold" 
    count=$((REPLICAS+1))
    echo "Updated No. of Replicas will be: "$count 
    scale=`$KUBECTL scale --replicas=$count deployment $DEPLOYMENT`
    echo "Deployment Scaled Up" 

  elif [ $AVGPODMEMPER -lt $SCALEDOWNTHRESHOLD ] && [ $REPLICAS -gt 2 ]
  then
    echo "Memory is less than threshold" 
    count=$((REPLICAS-1))
    echo "Updated No. of Replicas will be: "$count 
    scale=`$KUBECTL scale --replicas=$count deployment $DEPLOYMENT`
    echo "Deployment Scaled Down" 
  else
    echo "Memory is not crossing the threshold. No Scaling done." 
  fi
}

##########################################
#Calling Functions


if [[ $REPLICAS ]]; then
  if [ "$ACTION" = "get-podmemory" ];then
      echo "getting pod memory"
      #echo $ARG
      if [ $ARG -ne 4 ]
      then
        echo "Incorrect No. of Arguments Provided"
        print_help
        exit 1
      fi
      calculate_podmemory
  elif [ "$ACTION" = "deploy-pod-autoscaling" ];then
      if [ $ARG -ne 8 ]
      then
        echo "Incorrect No. of Arguments Provided"
        print_help
        exit 1
      fi
      calculate_podmemory
      podmemory_autoscale
  else
      echo "Unknown Action"
      print_help
  fi
else
  echo "No Deployment exists with name: "$DEPLOYMENT
  print_help
fi
