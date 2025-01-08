#!/bin/bash

LOG_FILE="monitorizare_$(date +%Y.%m.%d_%H:%M:%S).log"
OUT_LOG="out_$(date +%Y.%m.%d_%H:%M:%S).log"
PROCESSES=5 # numarul default de procese monitorizate
timp=60 # timpul default pt monitorizare periodica

# Redirectionarea STDOUT si STDERR catre out.log
exec > >(tee -a "$OUT_LOG") 2>&1

# Setarea Git pentru salvarea logurilor in cloud
function save_to_git() {
    git add "$OUT_LOG"
    git commit -m "Actualizare log: $(date +%Y.%m.%d_%H:%M:%S)"
    git push origin main
}

# Verificam dacă fisierul log exista, daca e nevoie il cream
if [ ! -f "$OUT_LOG" ]; then
    touch "$OUT_LOG"
fi

set -m
OPTIONS=$(getopt -o p: --long processes: -n 'script.sh' -- "$@")
eval set -- "$OPTIONS"
while true; do
    case "$1" in
        -p|--processes) 
            PROCESSES="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Optiune invalida." 
            exit 1
            ;;
    esac
done

function meniu_interactiv() {
    echo "==================================="
    echo "1) Monitorizare resurse"
    echo "2) Gestionare procese"
    echo "3) Monitorizare procese consumatoare de resurse"
    echo "4) Configurare resurse"
    echo "5) Terminare procese (soft/hard kill)"
    echo "6) Monitorizare periodica"
    echo "7) Iesire"
    echo "==================================="
    echo -n "Alegeti o optiune: "
}


function monitorizare_resurse() {
    touch "$LOG_FILE"
    echo "=== Monitorizare Resurse ===" >> "$LOG_FILE"
    echo "Resurse RAM:" | tee -a "$LOG_FILE"
    free -h | tee -a "$LOG_FILE"
    echo "Spatiu pe disc:" | tee -a "$LOG_FILE"
    df -h | tee -a "$LOG_FILE"
    echo "Utilizare CPU:" | tee -a "$LOG_FILE"
    top -bn1 | grep "Cpu(s)" | tee -a "$LOG_FILE"
    echo "Utilizare retea:" | tee -a "$LOG_FILE"
    cat /proc/net/dev | tee -a "$LOG_FILE"
    echo "Log salvat in $LOG_FILE"
}

function monitorizare_periodica() {
    while true; do
        monitorizare_resurse
        sleep $timp
    done
}

function porneste_opreste_monitorizare_periodica(){
    if [[ -z "$PERIODIC_PID" ]]; then
                echo "Pornim monitorizarea periodica..."
                monitorizare_periodica &
                PERIODIC_PID=$!
                echo "Monitorizare periodica ruland cu PID $PERIODIC_PID."
            else
                echo "Monitorizarea periodica este deja pornita. Doriti să o opriti? (da/nu): "
                read raspuns
                if [[ "$raspuns" == "da" ]]; then
                    kill "$PERIODIC_PID" 2>/dev/null
                    echo "Monitorizarea periodica oprita."
                    unset PERIODIC_PID
                else
                    echo "Monitorizarea periodica continua."
                fi
            fi
}

function monitorizare_top_procese() {
    echo "=== Top $PROCESSES Procese ===" | tee -a "$LOG_FILE"
    ps -eo pid,comm,%mem,%cpu --sort=-%cpu | head -n "$((PROCESSES + 1))" | tee -a "$LOG_FILE"
}


function gestionare_procese() {
    echo "=== Gestionare Procese ==="
    ps -eo pid,ppid,state,comm | tee -a "$LOG_FILE"
    echo -n "Alegeti o operatie (start/suspend/wait/background/foreground): "
    read operatie
    case "$operatie" in
        start)
            echo -n "Introduceti comanda pentru proces: "
            read comanda
            nohup $comanda &>> "$LOG_FILE" &
            echo "Proces pornit cu PID: $!" ;;
        suspend)
            echo -n "Introduceti PID-ul procesului de suspendat: "
            read pid
            kill -STOP "$pid"
            echo "Proces $pid suspendat." ;;
        wait)
            echo -n "Introduceti PID-ul procesului de asteptat: "
            read pid
            wait "$pid"
            echo "Proces $pid s-a terminat." ;;
        background)
            var=$(jobs)
            echo $var;
            echo -n "Introduceti ID-ul job-ului pentru background: "
            read pid
            bg "$pid" ;;
        foreground)
            var=$(jobs)
            echo $var;
            echo -n "Introduceti ID-ul job-ului pentru foreground: "
            read pid
            fg "$pid" ;;
        *)
            echo "Operatie invalida!" ;;
    esac
}

function configurare_resurse() {
    echo "=== Configurare Resurse ==="
    echo "1) Schimbare vm.swappiness"
    echo "2) Schimbare interval actualizare monitorizare"
    echo -n "Alegeti o optiune: "
    read optiune
    case "$optiune" in
        1)
            echo -n "Introduceti noua valoare pentru vm.swappiness (0-100): "
            read valoare
            if [[ "$valoare" =~ ^[0-9]+$ ]] && ((valoare >= 0 && valoare <= 100)); then
                sed -i "s/^vm.swappiness=.*/vm.swappiness=$valoare/" /etc/sysctl.conf
                sysctl -p
                echo "vm.swappiness actualizat la $valoare." | tee -a "$LOG_FILE"
            else
                echo "Valoare invalida!"
            fi ;;
        2)
            echo -n "Introduceti noul interval (in secunde): "
            read timpNou
            if [[ "$timp" =~ ^[0-9]+$ ]]; then
                echo "Interval setat la $timp secunde." | tee -a "$LOG_FILE"
                timp=$timpNou
                kill "$PERIODIC_PID" 2>/dev/null
                monitorizare_periodica &
                PERIODIC_PID=$!
            else
                echo "Valoare invalida!" 
            fi ;;
        *)
            echo "Optiune invalida!" ;;
    esac
}

function terminare_procese() {
    echo "=== Terminare Procese ==="
    echo -n "Introduceti PID-ul procesului: "
    read pid
    echo -n "Alegeti metoda (soft/hard): "
    read metoda
    case "$metoda" in
        soft)
            kill "$pid"
            echo "Proces $pid terminat (soft kill)." ;;
        hard)
            kill -9 "$pid"
            echo "Proces $pid terminat (hard kill)." ;;
        *)
            echo "Metoda invalida!" ;;
    esac
}

while true; do
    meniu_interactiv
    read optiune
    case $optiune in
        1) monitorizare_resurse ;;
        2) gestionare_procese ;;
        3) monitorizare_top_procese ;;
        4) configurare_resurse ;;
        5) terminare_procese ;;
        6) porneste_opreste_monitorizare_periodica ;;
        7) save_to_git
           break ;;
        *) echo "Optiune invalida." ;;
    esac
done
