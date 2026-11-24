# 초등 코바늘 키트 제작 제안서 — 이름만 바꿔 새로 만들기
#   python resources/proposals/make_proposal.py "받는 분 이름" "대표 전화번호" [출력 파일] ["둘째 문단(선택)"]
#   - 틀: kidskit_proposal_template.html ({{NAME}} · {{PHONE}} · {{WHY}})
#   - 전화번호는 이 저장소(공개)에 적지 않는다 → 실행할 때 넣고, 만든 파일은 저장소 밖(scratchpad)에 둔다
#   - 만든 파일을 Claude 페이지(Artifact)로 올려 링크를 보낸다(받는 분마다 새 페이지). 보내기 전에 공유 메뉴에서 열어야 함
import io, os, sys
here = os.path.dirname(os.path.abspath(__file__))
name, phone = sys.argv[1], sys.argv[2]
out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.environ.get('TEMP', '.'), 'proposal_kidskit_out.html')
why = sys.argv[4] if len(sys.argv) > 4 else '{name} 님의 작품을 보며, 작고 귀여운 소품을 쉽고 또렷하게 보여 주시는 방식이 아이들에게 꼭 맞겠다고 생각했습니다. 그래서 키트의 다음 다섯 작품을 함께 만들어 주실 수 있을지 여쭙니다.'
s = io.open(os.path.join(here, 'kidskit_proposal_template.html'), encoding='utf-8').read()
s = s.replace('{{WHY}}', why.replace('{name}', name)).replace('{{NAME}}', name).replace('{{PHONE}}', phone)
assert '{{' not in s, '바꾸지 못한 칸이 남았어요'
io.open(out, 'w', encoding='utf-8', newline='\n').write(s)
print(out)
