# DGX Spark 1대로 GLM-5.3-Flash 한 번에 서빙하기

인프라 지식이 없어도 NVIDIA DGX Spark 한 대에서 **GLM-5.3-Flash EXL3 2.05 bpw + DFlash2**를 OpenAI 호환 API로 실행하도록 만든 설치·운영 레포입니다. 모델 파일은 포함하지 않으며, 검증된 원본 리비전을 첫 실행 중 직접 내려받습니다.

이 레포는 [`gitcommit90/glm-5.3-one-spark`](https://github.com/gitcommit90/glm-5.3-one-spark)의 런타임·패치·고정 리비전을 그대로 기반으로 하고, [`DGXspark1-Qwen3.8-Flash-Next`](https://github.com/crimsonjoo/DGXspark1-Qwen3.8-Flash-Next)의 초보자용 설치·Compose 운영 흐름을 GLM에 맞게 적용했습니다.

## 가장 빠른 시작

DGX OS와 NVIDIA 드라이버가 설치되어 있고 `nvidia-smi`가 정상이라면:

```bash
git clone https://github.com/crimsonjoo/DGXspark1-GLM5.3-flash.git
cd DGXspark1-GLM5.3-flash
./start.sh
```

첫 실행은 다음 작업을 자동으로 진행합니다.

1. GB10 GPU, 드라이버, 운영체제 사전 점검
2. 필요할 때 Docker, Compose, NVIDIA Container Toolkit, OpenSSH 설치
3. SSH 사용자 `sejin` 확인 또는 생성
4. DFlash2 라이선스 안내 및 명시적 동의
5. 고정된 EXL3 모델 약 80 GiB와 DFlash2 약 2.2 GiB 다운로드(중단 후 재개 가능)
6. DGX Spark용 패치 vLLM 이미지 빌드
7. Compose로 GLM 서버와 선택적 watchdog 실행
8. health, 모델 목록, 실제 짧은 추론 검증
9. 감지된 모든 LAN IP의 API·health·SSH 명령 출력

시스템 패키지를 설치할 때만 `sudo` 암호를 요구합니다. NVIDIA 드라이버가 없거나 `nvidia-smi`가 실패하면 드라이버를 임의 변경하지 않고 중단합니다.

> DFlash2 체크포인트는 **CC BY-NC-ND 4.0 비상업 연구/평가 용도**입니다. 첫 실행에서 원문 링크를 보여주고 동의를 받습니다. 상업적 사용에는 Inco AI의 별도 허가가 필요합니다.

## 매일 쓰는 명령

```bash
./start.sh           # 최초 점검·설치·다운로드·빌드 후 서버 실행
./start.sh --check   # 아무것도 바꾸지 않는 읽기 전용 점검
./apply.sh           # .env.glm의 변경 설정을 Compose에 적용
./apply.sh --force   # 설정이 같아도 서버와 watchdog 재생성
./stop.sh            # 두 컨테이너 중지, 모델/이미지/캐시는 보존
./stop.sh --remove   # 컨테이너와 Compose 리소스 제거, 데이터는 보존
./stop.sh --status   # 현재 상태만 표시
```

첫 실행 때 저장소 루트에 `.env.glm`이 자동 생성되고 권한은 `600`으로 제한됩니다. Git에는 커밋되지 않습니다. 포트, 컨텍스트 길이, 동시 요청 수 등을 바꾼 뒤 `./apply.sh`를 실행하세요.

## 접속 방법

기본값은 API 키 없이 `0.0.0.0:18080`에서 서비스합니다. `./start.sh` 또는 `./apply.sh` 완료 화면에 실제 주소가 표시됩니다.

```bash
curl http://SPARK_LAN_IP:18080/v1/models

curl http://SPARK_LAN_IP:18080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"GLM-5.3-Flash-EXL3-2.05",
    "messages":[{"role":"user","content":"안녕하세요"}],
    "max_tokens":128,
    "chat_template_kwargs":{"enable_thinking":false}
  }'
```

Python OpenAI SDK에서는 키가 실제로 검증되지 않지만 SDK 형식상 임의 문자열을 넣습니다.

```python
from openai import OpenAI

client = OpenAI(base_url="http://SPARK_LAN_IP:18080/v1", api_key="unused")
result = client.chat.completions.create(
    model="GLM-5.3-Flash-EXL3-2.05",
    messages=[{"role": "user", "content": "안녕하세요"}],
    max_tokens=128,
)
print(result.choices[0].message.content)
```

인증이 없으므로 인터넷에 포트를 직접 노출하지 마세요. 신뢰할 수 있는 LAN/VPN에서 사용하거나, 공인 인터넷 제공 시 TLS와 인증이 있는 리버스 프록시를 앞에 두어야 합니다. 공유기 NAT/포트포워딩은 이 스크립트가 자동 변경하지 않습니다.

## 기본 설정과 모델 정보

| 항목 | 기본값 |
|---|---|
| 제공 모델명 | `GLM-5.3-Flash-EXL3-2.05` |
| API 포트 | `18080` |
| 컨텍스트 | `262144` |
| 동시 시퀀스 | `4` |
| GPU 메모리 비율 | `0.90` |
| DFlash2 speculative K | `5` |
| 재시작 정책 | `unless-stopped` |

K=5는 일반 대화·코딩용 기본값이고 구조화된 반복 출력 위주라면 `.env.glm`에서 `K=8`을 시험할 수 있습니다. 전체 262K 요청 네 개를 동시에 담을 만큼 KV 캐시가 크지는 않습니다.

정확히 고정된 원본:

- Target: `turboderp/GLM-5.3-Flash-exl3` revision `51058cd551c7e570d87bd32a4adee720edce2349`
- Drafter: `incoai/GLM-5.3-Flash-DFlash2` revision `bf582e4eacc1810f76656d1811693ff6c6737d2a`
- vLLM 기반 이미지와 패치 출처는 [PROVENANCE.md](PROVENANCE.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)에 기록되어 있습니다.

## 이미지 선택

기본값은 이 저장소의 고정 Dockerfile을 로컬에서 빌드하여 최신 포함 패치를 정확히 재현합니다. 빌드 시간을 줄이고 이미 공개된 upstream 이미지를 사용하려면 `.env.glm`을 다음처럼 변경합니다.

```bash
IMAGE=ghcr.io/gitcommit90/glm-5.3-one-spark:general23
BUILD_IMAGE=0
```

그 뒤 `./start.sh`를 다시 실행하면 이미지가 없을 때 자동 pull합니다.

## 문제 확인

```bash
docker logs -f glm53-one-spark
docker logs -f glm53-watchdog
curl http://127.0.0.1:18080/health
./scripts/smoke-test.sh http://127.0.0.1:18080
```

watchdog는 실행 중이지만 응답하지 않는 엔진만 제한 횟수 내에서 복구합니다. 사용자가 `./stop.sh`로 의도적으로 멈춘 서버를 다시 켜지는 않습니다. Docker 소켓 접근이 부담되면 `.env.glm`에서 `WATCHDOG=0`으로 바꾼 뒤 `./apply.sh`를 실행하세요.

## 라이선스

이 레포의 통합 코드는 MIT입니다. 포함된 파생 코드와 런타임 구성요소는 각각의 원 라이선스를 따릅니다. 모델 가중치는 내려받을 뿐 재배포하지 않습니다. 특히 DFlash2는 CC BY-NC-ND 4.0입니다.
