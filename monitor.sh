#!/bin/bash

LOG_FILE="/tmp/commands.log"

if [[ "$1" == "auto" ]]; then
    echo "설정 중..."

    # ------------------------------------------------------------------
    # 1) /etc/profile.d/monitor.sh 설치 (로그인 셸용: su - user, ssh 등)
    # ------------------------------------------------------------------
    sudo tee /etc/profile.d/monitor.sh > /dev/null << 'EOF'
# 수업용 명령어 모니터링
# bash가 아니면 종료 (dash 등에서 문법 오류 방지)
[ -n "$BASH_VERSION" ] || return 0

# 대화형 셸에서만 동작
case $- in
    *i*) ;;
    *) return 0 ;;
esac

MON_LOG="/tmp/commands.log"
touch "$MON_LOG" 2>/dev/null
chmod 666 "$MON_LOG" 2>/dev/null

# 셸 시작 시점의 마지막 히스토리 번호를 기억해둠
# (이전 세션에서 남은 .bash_history 마지막 줄이 로그되는 것 방지)
__mon_last=$(HISTTIMEFORMAT= history 1 | awk '{print $1}')

__mon_log() {
    # 탭 자동완성 중에는 무시
    [[ -n "$COMP_LINE" ]] && return

    local entry num cmd
    entry=$(HISTTIMEFORMAT= history 1)
    num=$(awk '{print $1}' <<< "$entry")

    # 히스토리 번호가 안 바뀌었으면 = 새 명령이 아님 (스킵)
    # 파이프라인(ls | grep)도 DEBUG가 여러 번 발동하지만 번호가 같아서 1번만 기록됨
    [[ -z "$num" || "$num" == "$__mon_last" ]] && return
    __mon_last=$num

    cmd=$(sed 's/^ *[0-9]\{1,\} *//' <<< "$entry")
    [[ -z "$cmd" ]] && return
    [[ "$cmd" == "exit" || "$cmd" == "logout" ]] && return

    printf '%s$ %s\n' "$(whoami)" "$cmd" >> "$MON_LOG"
}

# 핵심: PROMPT_COMMAND(명령 종료 후 실행) 대신 DEBUG trap(명령 실행 "직전" 발동)
# → vi, less 같은 명령도 실행하는 즉시 모니터 창에 표시됨
trap '__mon_log' DEBUG
EOF

    # ------------------------------------------------------------------
    # 2) 비로그인 셸 대응 (su user, sudo su, sudo bash 등)
    #    Debian/Ubuntu 계열은 비로그인 셸에서 /etc/profile.d를 안 읽으므로
    #    /etc/bash.bashrc 에 직접 후킹. (RHEL 계열은 /etc/bashrc가 이미
    #    profile.d를 읽어주므로 별도 조치 불필요)
    # ------------------------------------------------------------------
    if [[ -f /etc/bash.bashrc ]] && ! grep -q 'profile.d/monitor.sh' /etc/bash.bashrc; then
        echo '[ -f /etc/profile.d/monitor.sh ] && . /etc/profile.d/monitor.sh' \
            | sudo tee -a /etc/bash.bashrc > /dev/null
        echo "  -> /etc/bash.bashrc 후킹 완료 (비로그인 셸 대응)"
    fi

    echo "완료! 적용: source /etc/profile.d/monitor.sh"

elif [[ "$1" == "view" ]]; then
    clear
    touch "$LOG_FILE" 2>/dev/null

    # 실시간 모니터링
    tail -n 0 -f "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        user=$(echo "$line" | cut -d'$' -f1)
        cmd=$(echo "$line" | cut -d'$' -f2- | sed 's/^ *//')

        words=($cmd)
        output=""

        for i in "${!words[@]}"; do
            word="${words[$i]}"

            if [[ $i -eq 0 ]] || command -v "$word" &>/dev/null 2>&1 || \
               [[ "$word" == "cd" || "$word" == "su" || "$word" == "sudo" ]]; then
                output="$output \033[92m$word\033[0m"
            elif [[ "$word" == -* ]]; then
                output="$output \033[93m$word\033[0m"
            else
                output="$output \033[37m$word\033[0m"
            fi
        done

        echo -e "\033[36m${user}\$\033[0m$output"
    done

elif [[ "$1" == "clean" ]]; then
    > "$LOG_FILE"
    echo "로그 파일이 정리되었습니다."

elif [[ "$1" == "remove" ]]; then
    sudo rm -f /etc/profile.d/monitor.sh
    # bash.bashrc에 추가했던 후킹 라인도 제거
    if [[ -f /etc/bash.bashrc ]]; then
        sudo sed -i '/profile.d\/monitor.sh/d' /etc/bash.bashrc
    fi
    rm -f "$LOG_FILE"
    echo "모니터링 설정이 제거되었습니다."
    echo "(이미 열려있는 셸은 닫아야 trap이 사라집니다)"

elif [[ "$1" == "history" ]]; then
    if [[ -f "$LOG_FILE" ]]; then
        echo "=== 명령어 히스토리 ==="
        cat "$LOG_FILE" | while IFS= read -r line; do
            user=$(echo "$line" | cut -d'$' -f1)
            cmd=$(echo "$line" | cut -d'$' -f2- | sed 's/^ *//')
            echo -e "\033[36m${user}\$\033[0m $cmd"
        done
    else
        echo "로그 파일이 없습니다."
    fi

elif [[ "$1" == "test" ]]; then
    echo "=== 현재 설정 상태 ==="
    echo "LOG_FILE: $LOG_FILE"
    echo "Current User: $(whoami)"
    echo "SUDO_USER: $SUDO_USER"
    echo "DEBUG trap: $(trap -p DEBUG | grep -q __mon_log && echo '활성' || echo '비활성 (source 필요)')"

    if [[ -f /etc/profile.d/monitor.sh ]]; then
        echo "모니터링 스크립트: 설치됨"
    else
        echo "모니터링 스크립트: 설치 안됨"
    fi

    if [[ -f /etc/bash.bashrc ]]; then
        if grep -q 'profile.d/monitor.sh' /etc/bash.bashrc; then
            echo "비로그인 셸 후킹(/etc/bash.bashrc): 설치됨"
        else
            echo "비로그인 셸 후킹(/etc/bash.bashrc): 설치 안됨"
        fi
    fi

    if [[ -f "$LOG_FILE" ]]; then
        echo "로그 파일: 존재 ($(wc -l < "$LOG_FILE") 줄)"
    else
        echo "로그 파일: 없음"
    fi

else
    cat << EOF
사용법: $0 {auto|view|clean|remove|history|test}

  auto    - 자동 모니터링 설정 설치
  view    - 실시간 명령어 모니터링
  clean   - 로그 파일 정리
  remove  - 모니터링 설정 완전 제거
  history - 저장된 명령어 히스토리 보기
  test    - 현재 설정 상태 확인

예제:
  $0 auto              # 설정 설치
  source /etc/profile.d/monitor.sh  # 현재 세션에 적용
  $0 view              # 다른 터미널에서 실시간 모니터링
EOF
fi
