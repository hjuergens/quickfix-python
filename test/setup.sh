#!/bin/sh
#
# Generate cfg/at.cfg for the acceptance suite.
#
# Usage: setup.sh <port>

SCRIPT=$(realpath "$0")
DIR=$(dirname "$SCRIPT")
cd "$DIR" || exit 1

PORT=$1
case $PORT in
'' | *[!0-9]*)
  echo "usage: $0 <port>" >&2
  exit 2
  ;;
esac

mkdir -p cfg

cat > cfg/at.cfg <<EOF
[DEFAULT]
ConnectionType=acceptor
SocketAcceptPort=$PORT
SocketReuseAddress=Y
StartTime=00:00:00
EndTime=00:00:00
SenderCompID=ISLD
ResetOnLogon=Y
FileStorePath=store
[SESSION]
BeginString=FIX.4.0
TargetCompID=TW40
DataDictionary=../spec/FIX40.xml
[SESSION]
BeginString=FIX.4.1
TargetCompID=TW41
DataDictionary=../spec/FIX41.xml
[SESSION]
BeginString=FIX.4.2
TargetCompID=TW42
DataDictionary=../spec/FIX42.xml
[SESSION]
BeginString=FIX.4.3
TargetCompID=TW43
DataDictionary=../spec/FIX43.xml
[SESSION]
BeginString=FIX.4.4
TargetCompID=TW44
DataDictionary=../spec/FIX44.xml
[SESSION]
BeginString=FIXT.1.1
TargetCompID=TW50
DefaultApplVerID=FIX.5.0
TransportDataDictionary=../spec/FIXT11.xml
AppDataDictionary=../spec/FIX50.xml
[SESSION]
BeginString=FIXT.1.1
TargetCompID=TW50SP1
DefaultApplVerID=FIX.5.0SP1
TransportDataDictionary=../spec/FIXT11.xml
AppDataDictionary=../spec/FIX50SP1.xml
[SESSION]
BeginString=FIXT.1.1
TargetCompID=TW50SP2
DefaultApplVerID=FIX.5.0SP2
TransportDataDictionary=../spec/FIXT11.xml
AppDataDictionary=../spec/FIX50SP2.xml
[SESSION]
BeginString=FIX.4.4
TargetCompID=TW
DataDictionary=../spec/FIX44.xml
[SESSION]
BeginString=FIX.4.4
TargetCompID=NO_CHECK_FIELDS_HAVE_VALUES
DataDictionary=../spec/FIX44.xml
ValidateFieldsHaveValues=N
EOF
