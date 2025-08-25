#!/bin/bash

LOG_FILE="/tmp/commands.log"

if [[ "$1" == "auto" ]]; then
    echo "설정 중..."
    
    sudo tee /etc/profile.d/monitor.sh > /dev/null << 'EOF'
if [[ -n "$PS1" ]]; then
    LOG_FILE="/tmp/commands.log"
    touch "$LOG_FILE" && chmod 666 "$LOG_FILE" 2>/dev/null
    
    log_command() {
        local cmd=$(history 1 | sed 's/^ *[0-9]* *//')
        local current_user=$(whoami)
        
        # 빈 명령어 방지
        if [[ -z "$cmd" ]]; then
            return
        fi
        
        # exit 명령어는 로그하지 않음
        if [[ "$cmd" == "exit" || "$cmd" == "logout" ]]; then
            return
        fi
        
        # 중복 방지 (같은 사용자의 연속된 같은 명령어)
        if [[ -f "$LOG_FILE" ]]; then
            local last_line=$(tail -1 "$LOG_FILE" 2>/dev/null)
            local last_user=$(echo "$last_line" | cut -d'$' -f1)
            local last_cmd=$(echo "$last_line" | cut -d'$' -f2- | sed 's/^ *//')
            
            if [[ "$current_user" == "$last_user" && "$cmd" == "$last_cmd" ]]; then
                return
            fi
        fi
        
        # 로그 기록
        echo "${current_user}\$ $cmd" >> "$LOG_FILE"
    }
    
    # PROMPT_COMMAND 설정
    if [[ -z "$PROMPT_COMMAND" ]]; then
        PROMPT_COMMAND='log_command'
    else
        # 기존 PROMPT_COMMAND가 있으면 추가
        if [[ "$PROMPT_COMMAND" != *"log_command"* ]]; then
            PROMPT_COMMAND="${PROMPT_COMMAND};log_command"
        fi
    fi
    
    # su/sudo su 전환 시 즉시 사용자 정보 로그
    if [[ "$SUDO_USER" != "" && "$USER" == "root" ]]; then
        # sudo su로 root가 된 경우, 약간의 지연 후 확인
        (sleep 0.1 && echo "root\$ # Switched to root" >> "$LOG_FILE") &
    fi
fi
EOF
    
    echo "완료! 적용: source /etc/profile.d/monitor.sh"

elif [[ "$1" == "view" ]]; then
    clear
    
    # 실시간 모니터링
    tail -n 0 -f "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        # 사용자와 명령어 분리
        user=$(echo "$line" | cut -d'$' -f1)
        cmd=$(echo "$line" | cut -d'$' -f2- | sed 's/^ *//')
        
        # 주석 처리된 전환 메시지는 건너뛰기
        if [[ "$cmd" == "# Switched to root" ]]; then
            continue
        fi
        
        # 명령어를 단어별로 분리
        words=($cmd)
        output=""
        
        # 각 단어별로 색상 적용
        for i in "${!words[@]}"; do
            word="${words[$i]}"
            
            # 첫 번째 단어나 명령어인 경우 녹색
            if [[ $i -eq 0 ]] || command -v "$word" &>/dev/null 2>&1 || \
               [[ "$word" == "cd" || "$word" == "su" || "$word" == "sudo" ]]; then
                output="$output \033[92m$word\033[0m"
            # 옵션인 경우 노란색
            elif [[ "$word" == -* ]]; then
                output="$output \033[93m$word\033[0m"
            # 나머지는 흰색
            else
                output="$output \033[37m$word\033[0m"
            fi
        done
        
        # 출력
        echo -e "\033[36m${user}\$\033[0m$output"
    done

elif [[ "$1" == "clean" ]]; then
    > "$LOG_FILE"
    echo "로그 파일이 정리되었습니다."

elif [[ "$1" == "remove" ]]; then
    sudo rm -f /etc/profile.d/monitor.sh
    rm -f "$LOG_FILE"
    echo "모니터링 설정이 제거되었습니다."

elif [[ "$1" == "history" ]]; then
    # 저장된 로그 히스토리 보기
    if [[ -f "$LOG_FILE" ]]; then
        echo "=== 명령어 히스토리 ==="
        cat "$LOG_FILE" | while IFS= read -r line; do
            user=$(echo "$line" | cut -d'$' -f1)
            cmd=$(echo "$line" | cut -d'$' -f2- | sed 's/^ *//')
            
            # 전환 메시지 건너뛰기
            if [[ "$cmd" == "# Switched to root" ]]; then
                continue
            fi
            
            echo -e "\033[36m${user}\$\033[0m $cmd"
        done
    else
        echo "로그 파일이 없습니다."
    fi

elif [[ "$1" == "test" ]]; then
    # 테스트 모드 - 현재 설정 확인
    echo "=== 현재 설정 상태 ==="
    echo "LOG_FILE: $LOG_FILE"
    echo "PROMPT_COMMAND: $PROMPT_COMMAND"
    echo "Current User: $(whoami)"
    echo "SUDO_USER: $SUDO_USER"
    
    if [[ -f /etc/profile.d/monitor.sh ]]; then
        echo "모니터링 스크립트: 설치됨"
    else
        echo "모니터링 스크립트: 설치 안됨"
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
