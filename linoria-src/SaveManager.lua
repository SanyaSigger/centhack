local httpService = game:GetService('HttpService')

-- Escapes a value so it can safely live inside a pipe delimited record.
local function EscapeValue(Value)
	Value = tostring(Value)

	local out = {}
	local Index = 1
	local Length = #Value

	while Index <= Length do
		local Char = Value:sub(Index, Index)

		if Char == '\\' then
			table.insert(out, '\\\\')
		elseif Char == '|' then
			table.insert(out, '\\|')
		elseif Char == '\n' then
			table.insert(out, '\\n')
		elseif Char == '\r' then
			table.insert(out, '\\r')
		else
			table.insert(out, Char)
		end

		Index = Index + 1
	end

	return table.concat(out)
end

-- Reverses EscapeValue.
local function UnescapeValue(Value)
	local out = {}
	local Index = 1
	local Length = #Value

	while Index <= Length do
		local Char = Value:sub(Index, Index)

		if Char == '\\' and Index < Length then
			local Next = Value:sub(Index + 1, Index + 1)

			if Next == '|' or Next == '\\' then
				table.insert(out, Next)
				Index = Index + 2
			elseif Next == 'n' then
				table.insert(out, '\n')
				Index = Index + 2
			elseif Next == 'r' then
				table.insert(out, '\r')
				Index = Index + 2
			else
				table.insert(out, Char)
				Index = Index + 1
			end
		else
			table.insert(out, Char)
			Index = Index + 1
		end
	end

	return table.concat(out)
end

-- Splits a record into its fields, honouring escape sequences.
local function SplitRecord(Line)
	local parts = {}
	local buffer = {}
	local Index = 1
	local Length = #Line

	while Index <= Length do
		local Char = Line:sub(Index, Index)

		if Char == '\\' and Index < Length then
			local Next = Line:sub(Index + 1, Index + 1)

			if Next == '|' or Next == '\\' then
				table.insert(buffer, Char)
				table.insert(buffer, Next)
				Index = Index + 2
			else
				table.insert(buffer, Char)
				Index = Index + 1
			end
		elseif Char == '|' then
			table.insert(parts, table.concat(buffer))
			buffer = {}
			Index = Index + 1
		else
			table.insert(buffer, Char)
			Index = Index + 1
		end
	end

	table.insert(parts, table.concat(buffer))

	return parts
end

local SaveManager = {} do
	SaveManager.Folder = 'LinoriaLibSettings'
	SaveManager.Ignore = {}
	SaveManager.ConfigHeader = 'LinoriaCfg|1'
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object)
				return string.format('Toggle|%s|%s', EscapeValue(idx), tostring(object.Value and true or false))
			end,
			Load = function(idx, data)
				local Toggle = Toggles[idx] or Options[idx]

				if Toggle then
					Toggle:SetValue(data.value == 'true')
				end
			end
		},
		Slider = {
			Save = function(idx, object)
				return string.format('Slider|%s|%s', EscapeValue(idx), tostring(object.Value))
			end,
			Load = function(idx, data)
				local value = tonumber(data.value)

				if Options[idx] and value ~= nil then
					Options[idx]:SetValue(value)
				end
			end
		},
		Dropdown = {
			Save = function(idx, object)
				return string.format('Dropdown|%s|%s', EscapeValue(idx), EscapeValue(object.Value))
			end,
			Load = function(idx, data)
				if Options[idx] and data.value ~= nil then
					Options[idx]:SetValue(data.value)
				end
			end
		},
		ColorPicker = {
			Save = function(idx, object)
				local Lib = getgenv().Library
				local hex = Lib and Lib:ColorToHex(object.Value) or object.Value:ToHex()
				return string.format('ColorPicker|%s|%s|%s', EscapeValue(idx), hex, tostring(object.Transparency or 0))
			end,
			Load = function(idx, data)
				local Lib = getgenv().Library
				local color = Lib and Lib:ColorFromHex(data.value or 'ffffff') or Color3.fromHex(data.value or 'ffffff')

				if Options[idx] then
					Options[idx]:SetValueRGB(color, tonumber(data.transparency) or 0)
				end
			end
		},
		KeyPicker = {
			Save = function(idx, object)
				return string.format('KeyPicker|%s|%s|%s', EscapeValue(idx), EscapeValue(object.Value), EscapeValue(object.Mode or 'Toggle'))
			end,
			Load = function(idx, data)
				if Options[idx] and data.key then
					Options[idx]:SetValue({ data.key, data.mode })
				end
			end
		},

		Input = {
			Save = function(idx, object)
				return string.format('Input|%s|%s', EscapeValue(idx), EscapeValue(object.Value or ''))
			end,
			Load = function(idx, data)
				if Options[idx] and type(data.text) == 'string' then
					Options[idx]:SetValue(data.text)
				end
			end
		},
	}

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.Folder = folder;
		self:BuildFolderTree()
	end

	function SaveManager:Save(name)
		if (not name) then
			return false, 'no config file is selected'
		end

		local fullPath = self.Folder .. '/settings/' .. name .. '.cfg'

		local encoded = self:EncodeConfig()

		writefile(fullPath, encoded)
		return true
	end

	function SaveManager:EncodeConfig()
		local objects = {}

		for idx, toggle in next, Toggles do
			if self.Ignore[idx] then continue end
			table.insert(objects, self.Parser[toggle.Type].Save(idx, toggle))
		end

		for idx, option in next, Options do
			if not self.Parser[option.Type] then continue end
			if self.Ignore[idx] then continue end

			table.insert(objects, self.Parser[option.Type].Save(idx, option))
		end

		local lines = {}
		table.insert(lines, 'LinoriaCfg|1')
		for _, obj in next, objects do
			table.insert(lines, obj)
		end

		return table.concat(lines, '\n')
	end

	function SaveManager:DecodeConfig(text)
		if type(text) ~= 'string' then
			return false, 'invalid config format'
		end

		local objects = {}
		local lines = {}

		for line in text:gmatch('[^\r\n]+') do
			table.insert(lines, line)
		end

		if #lines == 0 or lines[1] ~= self.ConfigHeader then
			return false, 'invalid config format'
		end

		for i = 2, #lines do
			local line = lines[i]

			-- Skip blank lines and comments
			if line:match('^%s*$') == nil and line:sub(1, 1) ~= '#' then
				local parts = SplitRecord(line)
				local objType = parts[1]

				if self.Parser[objType] then
					local data = { type = objType }

					if objType == 'Toggle' then
						data.idx = UnescapeValue(parts[2] or '')
						data.value = parts[3]
					elseif objType == 'Slider' then
						data.idx = UnescapeValue(parts[2] or '')
						data.value = parts[3]
					elseif objType == 'Dropdown' then
						data.idx = UnescapeValue(parts[2] or '')
						data.value = UnescapeValue(parts[3] or '')
					elseif objType == 'ColorPicker' then
						data.idx = UnescapeValue(parts[2] or '')
						data.value = parts[3]
						data.transparency = parts[4]
					elseif objType == 'KeyPicker' then
						data.idx = UnescapeValue(parts[2] or '')
						data.key = UnescapeValue(parts[3] or 'None')
						data.mode = UnescapeValue(parts[4] or 'Toggle')
					elseif objType == 'Input' then
						data.idx = UnescapeValue(parts[2] or '')
						-- The remainder of the line belongs to the input value
						data.text = UnescapeValue(table.concat(parts, '|', 3))
					end

					table.insert(objects, data)
				end
			end
		end

		for _, option in next, objects do
			if self.Parser[option.type] then
				self.Parser[option.type].Load(option.idx, option)
			end
		end

		return true
	end

	function SaveManager:ExportConfig()
		return self:EncodeConfig()
	end

	function SaveManager:ImportConfig(text)
		local success, err = self:DecodeConfig(text)
		if not success then
			return false, err
		end
		return true
	end

	function SaveManager:Load(name)
		if (not name) then
			return false, 'no config file is selected'
		end
		
		local file = self.Folder .. '/settings/' .. name .. '.cfg'
		if not isfile(file) then return false, 'invalid file' end

		local content = readfile(file)
		return self:DecodeConfig(content)
	end

	function SaveManager:IgnoreThemeSettings()
		self:SetIgnoreIndexes({ 
			"BackgroundColor", "MainColor", "AccentColor1", "AccentColor2", "OutlineColor", "FontColor", -- themes
			"ThemeManager_UseGradient", -- themes
			"ThemeManager_FontName", "ThemeManager_FontSize", -- typography
			"ThemeManager_BackgroundImage", "ThemeManager_BackgroundImageTransparency", "ThemeManager_BackgroundBlur", -- background
			"ThemeManager_ThemeList", 'ThemeManager_CustomThemeList', 'ThemeManager_CustomThemeName', -- themes
		})
	end

	function SaveManager:BuildFolderTree()
		local paths = {
			self.Folder,
			self.Folder .. '/themes',
			self.Folder .. '/settings'
		}

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function SaveManager:RefreshConfigList()
		local list = listfiles(self.Folder .. '/settings')

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-4) == '.cfg' then
				-- i hate this but it has to be done ...

				local pos = file:find('.cfg', 1, true)
				local start = pos

				local char = file:sub(pos, pos)
				while char ~= '/' and char ~= '\\' and char ~= '' do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == '/' or char == '\\' then
					table.insert(out, file:sub(pos + 1, start - 1))
				end
			end
		end
		
		return out
	end

	function SaveManager:SetLibrary(library)
		self.Library = library
	end

	function SaveManager:LoadAutoloadConfig()
		if isfile(self.Folder .. '/settings/autoload.txt') then
			local name = readfile(self.Folder .. '/settings/autoload.txt')

			local success, err = self:Load(name)
			if not success then
				return self.Library:Notify('Failed to load autoload config: ' .. err)
			end

			self.Library:Notify(string.format('Auto loaded config %q', name))
		end
	end


	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, 'Must set SaveManager.Library')

		local section = tab:AddRightGroupbox('Configuration')

		section:AddInput('SaveManager_ConfigName',    { Text = 'Config name' })
		section:AddDropdown('SaveManager_ConfigList', { Text = 'Config list', Values = self:RefreshConfigList(), AllowNull = true })

		section:AddDivider()

		section:AddButton('Create config', function()
			local name = Options.SaveManager_ConfigName.Value

			if name:gsub(' ', '') == '' then 
				return self.Library:Notify('Invalid config name (empty)', 2)
			end

			local success, err = self:Save(name)
			if not success then
				return self.Library:Notify('Failed to save config: ' .. err)
			end

			self.Library:Notify(string.format('Created config %q', name))

			Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
			Options.SaveManager_ConfigList:SetValue(nil)
		end):AddButton('Load config', function()
			local name = Options.SaveManager_ConfigList.Value

			local success, err = self:Load(name)
			if not success then
				return self.Library:Notify('Failed to load config: ' .. err)
			end

			self.Library:Notify(string.format('Loaded config %q', name))
		end)

		section:AddButton('Overwrite config', function()
			local name = Options.SaveManager_ConfigList.Value

			local success, err = self:Save(name)
			if not success then
				return self.Library:Notify('Failed to overwrite config: ' .. err)
			end

			self.Library:Notify(string.format('Overwrote config %q', name))
		end)

		section:AddDivider()

		section:AddButton('Export to clipboard', function()
			local cfgText = self:ExportConfig()
			if setclipboard then
				setclipboard(cfgText)
				self.Library:Notify('Config copied to clipboard!')
			else
				self.Library:Notify('setclipboard not available in this executor', 3)
			end
		end)

		section:AddInput('SaveManager_ImportConfig', {
			Text = 'Paste config here';
			Placeholder = 'Paste .cfg config text...';
		})

		section:AddButton('Load from text', function()
			local text = Options.SaveManager_ImportConfig.Value
			if text:gsub(' ', '') == '' then
				return self.Library:Notify('No config text to load', 2)
			end

			local success, err = self:ImportConfig(text)
			if not success then
				return self.Library:Notify('Failed to load config: ' .. err, 3)
			end

			self.Library:Notify('Config loaded from text!')

			Options.SaveManager_ImportConfig:SetValue('')
		end)

		section:AddButton('Refresh list', function()
			Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
			Options.SaveManager_ConfigList:SetValue(nil)
		end)

		section:AddButton('Set as autoload', function()
			local name = Options.SaveManager_ConfigList.Value
			writefile(self.Folder .. '/settings/autoload.txt', name)
			SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
			self.Library:Notify(string.format('Set %q to auto load', name))
		end)

		SaveManager.AutoloadLabel = section:AddLabel('Current autoload config: none', true)

		if isfile(self.Folder .. '/settings/autoload.txt') then
			local name = readfile(self.Folder .. '/settings/autoload.txt')
			SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
		end

		SaveManager:SetIgnoreIndexes({ 'SaveManager_ConfigList', 'SaveManager_ConfigName', 'SaveManager_ImportConfig' })
	end

	SaveManager:BuildFolderTree()
end

return SaveManager
