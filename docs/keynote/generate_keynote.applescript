-- Keynote Presentation Generator
-- テキストファイルからKeynoteプレゼンテーションを自動生成（1ファイルに統合）

on run
	-- 設定
	set keynoteFolder to "/Users/daisuketsukada/Documents/dsgarageiOS/ydevARApp/docs/keynote/"

	tell application "Keynote"
		activate

		-- 新規プレゼンテーション作成（インダストリアルテーマ）
		set newDoc to make new document with properties {document theme:theme "インダストリアル"}

		-- 最初のスライドを削除（デフォルトで作成されるため）
		tell newDoc
			if (count of slides) > 0 then
				delete slide 1
			end if
		end tell

		-- 3つのセクションを順番に追加
		my addSectionSlides("01", keynoteFolder, newDoc)
		my addSectionSlides("02", keynoteFolder, newDoc)
		my addSectionSlides("03", keynoteFolder, newDoc)

		-- ファイルを保存
		set savePath to (keynoteFolder & "AR勉強会資料.key") as POSIX file
		save newDoc in savePath
	end tell

	display dialog "Keynoteプレゼンテーションを生成しました（60スライド）" buttons {"OK"} default button "OK"
end run

on addSectionSlides(prefix, folderPath, theDoc)
	-- ファイル一覧を取得
	set textFiles to do shell script "ls " & quoted form of folderPath & prefix & "_*.txt | sort"
	set fileList to paragraphs of textFiles

	tell application "Keynote"
		tell theDoc
			-- 各テキストファイルからスライドを作成
			repeat with filePath in fileList
				set fileContent to do shell script "cat " & quoted form of filePath
				set contentLines to paragraphs of fileContent

				-- ファイル名からタイトルを抽出
				set fileName to do shell script "basename " & quoted form of filePath & " .txt"
				-- 01_p01_タイトル → タイトル部分を抽出
				set slideTitle to do shell script "echo " & quoted form of fileName & " | sed 's/^[0-9]*_p[0-9]*_//'"

				-- 本文を構築（1行目はタイトルなのでスキップ、行番号を除去、全角スペースを半角スペース4つに変換）
				set bodyText to ""
				set isFirstLine to true
				set foundBodyStart to false
				repeat with i from 1 to count of contentLines
					set currentLine to item i of contentLines
					-- 行番号プレフィックス（数字+→）を除去
					set cleanLine to do shell script "echo " & quoted form of currentLine & " | sed 's/^[[:space:]]*[0-9]*→//'"

					-- 1行目（タイトル）はスキップ
					if isFirstLine then
						set isFirstLine to false
					else
						-- 全角スペースを半角スペース4つに変換（視覚的インデント）
						set cleanLine to do shell script "echo " & quoted form of cleanLine & " | sed 's/　/    /g'"

						-- タイトル直後の空行をスキップして本文開始を検出
						if not foundBodyStart then
							if cleanLine is not "" then
								set foundBodyStart to true
							end if
						end if

						-- 本文開始後のみ追加
						if foundBodyStart then
							if cleanLine is not "" then
								if bodyText is "" then
									set bodyText to cleanLine
								else
									set bodyText to bodyText & return & cleanLine
								end if
							else if bodyText is not "" then
								set bodyText to bodyText & return
							end if
						end if
					end if
				end repeat

				-- 末尾の改行を除去
				repeat while bodyText ends with return
					set bodyText to text 1 thru -2 of bodyText
				end repeat

				-- スライドを追加
				if slideTitle contains "タイトル" then
					set newSlide to make new slide with properties {base layout:slide layout "タイトル（中央）"}
					tell newSlide
						set object text of default title item to slideTitle
					end tell
				else
					-- 6番目のレイアウト（タイトル&箇条書き）を使用
					set newSlide to make new slide with properties {base layout:slide layout 6}
					tell newSlide
						set object text of default title item to slideTitle
						tell default body item
							set object text to bodyText
						end tell
					end tell
				end if
			end repeat
		end tell
	end tell
end addSectionSlides
