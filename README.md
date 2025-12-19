# Olimpiada-Inowacyjno-ci-Elektronika
Aplikacja:
-wyświetlanie zapisu na graficznej szachownicy;
-analiza zagranych parti;
-podgląd parti na graficznej szachownicy;
-dokładna analiza w każdym momencie rozgrywki;

Raspberry:
-aktywna analiza w trakcie gry na zegarze;
-lepszy wyglad zegara;
-dodanie zróżnicowania w poziomie trudności pod względem szybkości ruchów;
-zarządzanie ramieniem;
-komunikacja z esp32;
-zbieranie danych z czujników szachowincy;

Esp32:
-przekazywanie sygnałów do sterownika serw;

Instrukcja:
Plik serwer.py należy uruchomić na raspberry pi 4 lub wyżej. W razie problemów z połaczeniem w osobnym oknie wydac polecenie "sudo bluetoothctl" aby móc zatwierdzic parowanie.
Folder "aplikacja_szachowa" zawiera pliki aplikacji mobilnej. Należy zainstalować framework flutter aby móc ja wgrać na urządzenie.