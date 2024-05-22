#!/bin/bash

# Init Config
userName="logonebihrapi"
passWord="passwdebihrapi"
apiUrl="https://api.bihr.net/api/v2.1"
downloadPath="stocks"  # Zakładam, że skrypt jest uruchamiany z 'public_html'
newFileName="stocks.csv"

function download_and_process {
  # eBihr Token generation
  response=$(curl -s -X 'POST' \
    "$apiUrl/Authentication/Token" \
    -H 'Content-Type: multipart/form-data' \
    -F "UserName=$userName" \
    -F "PassWord=$passWord")

  token=$(echo $response | grep -oP '"access_token":"\K[^"]*')

  if [ -z "$token" ]; then
    echo "Nie udało się uzyskać tokena. Sprawdź odpowiedź serwera."
    return 1
  fi

  echo "Uzyskano token: $token"

  # Generating ZIP file
  response=$(curl -s -X 'POST' \
    "$apiUrl/Catalog/ZIP/CSV/Stocks/Full" \
    -H "Authorization: Bearer $token" \
    -H 'accept: text/plain')

  ticketId=$(echo $response | grep -oP '"TicketId":"\K[^"]*')

  if [ -z "$ticketId" ]; then
    echo "Nie udało się zainicjować generowania pliku. Sprawdź odpowiedź serwera."
    return 1
  fi

  echo "Ticket ID: $ticketId"

  # Get file generation status
  while true; do
    statusResponse=$(curl -s -X 'GET' \
      "$apiUrl/Catalog/GenerationStatus?ticketId=$ticketId" \
      -H "Authorization: Bearer $token" \
      -H 'accept: text/plain')

    status=$(echo $statusResponse | grep -oP '"RequestStatus":"\K[^"]*')

    echo "Status: $status"

    if [ "$status" == "DONE" ]; then
      downloadId=$(echo $statusResponse | grep -oP '"DownloadId":"\K[^"]*')
      echo "Generowanie pliku zakończone. Download ID: $downloadId"
      break
    fi
    sleep 2
  done

  # Download ZIP file
  zipFilePath="$downloadPath/temp_stocks.zip"
  echo "Ścieżka zapisu ZIP: $zipFilePath"

  curl -s -X 'GET' \
    "$apiUrl/Catalog/GeneratedFile?downloadId=$downloadId" \
    -H "Authorization: Bearer $token" \
    -H 'accept: */*' \
    -o "$zipFilePath"

  # Extract ZIP file
  echo "Rozpoczynanie wypakowywania..."
  unzip -o "$zipFilePath" -d "$downloadPath"
  rm "$zipFilePath"

  # Change file name
  csvFilePath=$(find $downloadPath -maxdepth 1 -type f -name '*.csv' -print -quit)
  if [ -f "$downloadPath/$newFileName" ]; then
    rm "$downloadPath/$newFileName" # Usuwamy istniejący plik
  fi
  if [ -n "$csvFilePath" ]; then
    echo "Zmieniam nazwę z $csvFilePath na $downloadPath/$newFileName"
    mv "$csvFilePath" "$downloadPath/$newFileName"
    if [ $? -eq 0 ]; then
      echo "Plik CSV został zapisany jako: $downloadPath/$newFileName"
      return 0  # If file saved correctly, end script
    else
      echo "Nie udało się zmienić nazwy pliku. Błąd $?"
      return 1  # If filename change fail, return fault
    fi
  else
    echo "Nie znaleziono pliku CSV po wypakowaniu."
    return 1  # Return fault if file can't be find by filesystem
  fi
}

# If errorcode = 1, relaunch script
if ! download_and_process; then
  echo "Pierwsza próba nie powiodła się, próbuję ponownie..."
  download_and_process
fi
