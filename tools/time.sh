#!/bin/bash
# 커밋 간격 합산. 2시간 넘는 간격은 자리 비운 것으로 보고 제외.
git log --reverse --format=%ct | awk '
  NR>1 { d=$1-p; if (d<7200) s+=d } { p=$1 }
  END { printf "누적 개발 시간: %d시간 %d분\n", s/3600, (s%3600)/60 }'
