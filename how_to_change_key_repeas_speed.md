## 現在のキーリピート速度を表示
defaults read -g KeyRepeat

## 現在のキーリピート開始速度を表示
defaults read -g InitialKeyRepeat


## キーリピート速度を1に設定（小さい程速い）
defaults write -g KeyRepeat -int 1

## キーリピート開始速度の早さを10に設定（小さい程早い）
defaults write -g InitialKeyRepeat -int 10



## キーリピート速度をデフォルトに戻す
defaults delete -g KeyRepeat

## キーリピート開始速度をデフォルトに戻す
defaults delete -g InitialKeyRepeat

