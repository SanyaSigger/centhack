local httpService = game:GetService('HttpService')

-- Only fonts that exist on Enum.Font. Built by probing each name with pcall
-- so missing members (SourceSansBoldItalic, World, GothamSemibold, …) never crash.
local FONT_CANDIDATES = {
	'Legacy', 'Arial', 'ArialBold',
	'SourceSans', 'SourceSansBold', 'SourceSansLight', 'SourceSansItalic', 'SourceSansSemibold',
	'Bodoni', 'Garamond', 'Cartoon', 'Code', 'Highway', 'SciFi', 'Arcade', 'Fantasy', 'Antique',
	'Gotham', 'GothamMedium', 'GothamBold', 'GothamBlack',
	'AmaticSC', 'Bangers', 'Creepster', 'DenkOne', 'Fondamento', 'FredokaOne', 'GrenzeGotisch',
	'IndieFlower', 'JosefinSans', 'Jura', 'Kalam', 'LuckiestGuy', 'Merriweather', 'Michroma',
	'Nunito', 'Oswald', 'PatrickHand', 'PermanentMarker', 'Roboto', 'RobotoCondensed', 'RobotoMono',
	'Sarpanch', 'SpecialElite', 'TitilliumWeb', 'Ubuntu',
	'BuilderSans', 'BuilderSansMedium', 'BuilderSansBold', 'BuilderSansExtraBold',
	'Arimo', 'ArimoBold',
}

local function ResolveFont(name)
	if type(name) ~= 'string' or name == '' then
		return Enum.Font.Code
	end

	local ok, font = pcall(function()
		return Enum.Font[name]
	end)

	if ok and font ~= nil then
		return font
	end

	return Enum.Font.Code
end

local function GetAvailableFontNames()
	local names = {}

	for _, name in ipairs(FONT_CANDIDATES) do
		local ok, font = pcall(function()
			return Enum.Font[name]
		end)

		if ok and font ~= nil then
			table.insert(names, name)
		end
	end

	-- Fallback so the dropdown is never empty on weird executors.
	if #names == 0 then
		table.insert(names, 'Code')
	end

	table.sort(names)
	return names
end

local ThemeManager = {} do
	ThemeManager.Folder = 'LinoriaLibSettings'
	-- if not isfolder(ThemeManager.Folder) then makefolder(ThemeManager.Folder) end

	ThemeManager.Library = nil
	ThemeManager.FontNames = GetAvailableFontNames()
	ThemeManager.BuiltInThemes = {
		['Default'] 		= { 1, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1c1c1c","AccentColor1":"ffffff","AccentColor2":"ff5aa0","UseGradient":true,"GradientDirection":"Horizontal","BackgroundColor":"141414","OutlineColor":"323232","FontName":"Arcade","FontSize":15}') },
		['BBot'] 			= { 2, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1e1e","AccentColor1":"7e48a3","AccentColor2":"3b82f6","UseGradient":true,"GradientDirection":"Horizontal","BackgroundColor":"232323","OutlineColor":"141414"}') },
		['Fatality']		= { 3, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1842","AccentColor1":"c50754","AccentColor2":"7c3aed","UseGradient":true,"GradientDirection":"Horizontal","BackgroundColor":"191335","OutlineColor":"3c355d"}') },
		['Jester'] 			= { 4, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor1":"db4467","AccentColor2":"f59e0b","UseGradient":true,"GradientDirection":"Horizontal","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
		['Mint'] 			= { 5, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor1":"3db488","AccentColor2":"22d3ee","UseGradient":true,"GradientDirection":"Horizontal","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
		['Tokyo Night'] 	= { 6, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"191925","AccentColor1":"6759b3","AccentColor2":"38bdf8","UseGradient":true,"GradientDirection":"Horizontal","BackgroundColor":"16161f","OutlineColor":"323232"}') },
		['Ubuntu'] 			= { 7, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"3e3e3e","AccentColor1":"e2581e","AccentColor2":"facc15","UseGradient":true,"GradientDirection":"Horizontal","BackgroundColor":"323232","OutlineColor":"191919"}') },
		['Quartz'] 			= { 8, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"232330","AccentColor1":"426e87","AccentColor2":"a78bfa","UseGradient":true,"GradientDirection":"Horizontal","BackgroundColor":"1d1b26","OutlineColor":"27232f"}') },
	}

	function ThemeManager:ThemeUpdate()
		self.Library:UpdateColorsUsingRegistry()
		self.Library:UpdateGradients()
	end

	function ThemeManager:ApplyTheme(theme)
		local customThemeData = self:GetCustomTheme(theme)
		local data = customThemeData or self.BuiltInThemes[theme]
	
		if not data then return end
	
		-- custom themes are just regular dictionaries instead of an array with { index, dictionary }
		local scheme = data[2]
		local colorFields = {
			FontColor = true;
			MainColor = true;
			AccentColor1 = true;
			AccentColor2 = true;
			BackgroundColor = true;
			OutlineColor = true;
		}
	
		for idx, col in next, customThemeData or scheme do
			if colorFields[idx] then
				local color = self.Library:ColorFromHex(col)
				self.Library[idx] = color
				
				local opt = Options[idx]
				if opt and opt.SetValueRGB then
					pcall(opt.SetValueRGB, opt, color)
				end
			elseif idx == 'UseGradient' then
				self.Library.UseGradient = true
			elseif idx == 'GradientDirection' then
				if Options.ThemeManager_GradientDirection then
					Options.ThemeManager_GradientDirection:SetValue(col)
				end
			elseif idx == 'FontName' then
				if Options.ThemeManager_FontName then
					Options.ThemeManager_FontName:SetValue(col)
				end
			elseif idx == 'FontSize' then
				if Options.ThemeManager_FontSize then
					Options.ThemeManager_FontSize:SetValue(tonumber(col) or 14)
				end
			end
		end
	
		self:ThemeUpdate()
	end


	function ThemeManager:LoadDefault()		
		local theme = 'Default'
		local content = isfile(self.Folder .. '/themes/default.txt') and readfile(self.Folder .. '/themes/default.txt')

		local isDefault = true
		if content then
			if self.BuiltInThemes[content] then
				theme = content
			elseif self:GetCustomTheme(content) then
				theme = content
				isDefault = false;
			end
		elseif self.BuiltInThemes[self.DefaultTheme] then
		 	theme = self.DefaultTheme
		end

		if isDefault then
			Options.ThemeManager_ThemeList:SetValue(theme)
		else
			self:ApplyTheme(theme)
		end
	end

	function ThemeManager:SaveDefault(theme)
		writefile(self.Folder .. '/themes/default.txt', theme)
	end

	function ThemeManager:CreateThemeManager(groupbox)
		local function UpdateTheme()
			self:ThemeUpdate()
		end

		local function BindChanged(obj, callback)
			if obj and obj.OnChanged then
				obj:OnChanged(callback)
			end

		groupbox:AddColorPicker('BackgroundColor', {
			Title = 'Background color';
			Text = 'Background color';
			Default = self.Library.BackgroundColor;
			Callback = function(Value)
				self.Library.BackgroundColor = Value;
				UpdateTheme();
			end;
		});
		groupbox:AddColorPicker('MainColor', {
			Title = 'Main color';
			Text = 'Main color';
			Default = self.Library.MainColor;
			Callback = function(Value)
				self.Library.MainColor = Value;
				UpdateTheme();
			end;
		});
		groupbox:AddLabel('Accent colors (gradient always on)')
		groupbox:AddColorPicker('AccentColor1', {
			Title = 'Accent start';
			Text = 'Gradient start';
			Default = self.Library.AccentColor1;
			Callback = function(Value)
				self.Library.AccentColor1 = Value;
				UpdateTheme();
			end;
		});
		groupbox:AddColorPicker('AccentColor2', {
			Title = 'Accent end';
			Text = 'Gradient end';
			Default = self.Library.AccentColor2;
			Callback = function(Value)
				self.Library.AccentColor2 = Value;
				UpdateTheme();
			end;
		});
		groupbox:AddLabel('Gradient direction')
		groupbox:AddDropdown('ThemeManager_GradientDirection', {
			Text = 'Direction';
			Values = {'Horizontal', 'Vertical' };
			Default = self.Library.GradientDirection;
			Callback = function(Value)
				self.Library.GradientDirection = Value;
				UpdateTheme();
			end;
		});
		groupbox:AddColorPicker('OutlineColor', {
			Title = 'Outline color';
			Text = 'Outline color';
			Default = self.Library.OutlineColor;
			Callback = function(Value)
				self.Library.OutlineColor = Value;
				UpdateTheme();
			end;
		});
		groupbox:AddColorPicker('FontColor', {
			Title = 'Font color';
			Text = 'Font color';
			Default = self.Library.FontColor;
			Callback = function(Value)
				self.Library.FontColor = Value;
				UpdateTheme();
			end;
		});



		groupbox:AddDivider()

		groupbox:AddLabel('Font name')
		groupbox:AddDropdown('ThemeManager_FontName', {
			Text = 'Font';
			Values = self.FontNames;
			Default = self.Library.FontName or 'Code';
			Callback = function(Value)
				self.Library.FontName = Value;
				local ok, font = pcall(function() return Enum.Font[Value] end);
				self.Library.Font = (ok and font) or Enum.Font.Code;
				UpdateTheme();
			end;
		});

		groupbox:AddSlider('ThemeManager_FontSize', {
			Text = 'Font size';
			Default = self.Library.FontSize;
			Min = 8;
			Max = 32;
			Rounding = 0;
			Callback = function(Value)
				self.Library.FontSize = Value;
				UpdateTheme();
			end;
		});

		groupbox:AddDivider()

		local ThemesArray = {}
		for Name, Theme in next, self.BuiltInThemes do
			table.insert(ThemesArray, Name)
		end

		table.sort(ThemesArray, function(a, b) return self.BuiltInThemes[a][1] < self.BuiltInThemes[b][1] end)

		groupbox:AddDivider()
		groupbox:AddDropdown('ThemeManager_ThemeList', { Text = 'Theme list', Values = ThemesArray, Default = 1 })

		groupbox:AddButton('Set as default', function()
			self:SaveDefault(Options.ThemeManager_ThemeList.Value)
			self.Library:Notify(string.format('Set default theme to %q', Options.ThemeManager_ThemeList.Value))
		end)

		if Options.ThemeManager_ThemeList then
			Options.ThemeManager_ThemeList:OnChanged(function()
				self:ApplyTheme(Options.ThemeManager_ThemeList.Value)
				end)
		end

		groupbox:AddDivider()
		groupbox:AddInput('ThemeManager_CustomThemeName', { Text = 'Custom theme name' })
		groupbox:AddDropdown('ThemeManager_CustomThemeList', { Text = 'Custom themes', Values = self:ReloadCustomThemes(), AllowNull = true, Default = 1 })
		groupbox:AddDivider()
		
		groupbox:AddButton('Save theme', function() 
			self:SaveCustomTheme(Options.ThemeManager_CustomThemeName.Value)

			Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			Options.ThemeManager_CustomThemeList:SetValue(nil)
		end):AddButton('Load theme', function() 
			self:ApplyTheme(Options.ThemeManager_CustomThemeList.Value) 
		end)

		groupbox:AddButton('Refresh list', function()
			Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			Options.ThemeManager_CustomThemeList:SetValue(nil)
		end)


		ThemeManager:LoadDefault()



		groupbox:AddDivider()
		
		groupbox:AddLabel('Gradient animation')
		groupbox:AddToggle('ThemeManager_Move', {
			Text = 'Move gradient';
			Default = false;
			Callback = function(Value)
				ThemeManager.Moving = Value;
				if Value then
					ThemeManager.StartMove();
				else
					ThemeManager.StopMove();
				end;
			end;
		});

		end


	end
	function ThemeManager:GetCustomTheme(file)
		local path = self.Folder .. '/themes/' .. file
		if not isfile(path) then
			return nil
		end

		local data = readfile(path)
		local success, decoded = pcall(httpService.JSONDecode, httpService, data)
		
		if not success then
			return nil
		end

		return decoded
	end

	function ThemeManager:SaveCustomTheme(file)
		if file:gsub(' ', '') == '' then
			return self.Library:Notify('Invalid file name for theme (empty)', 3)
		end

		local theme = {}
		local fields = { "FontColor", "MainColor", "AccentColor1", "AccentColor2", "BackgroundColor", "OutlineColor" }

		for _, field in next, fields do
			if Options[field] then
				theme[field] = self.Library:ColorToHex(Options[field].Value)
			end
		end

		theme.UseGradient = true

		-- Gradient direction
		if Options.ThemeManager_GradientDirection then
			theme.GradientDirection = Options.ThemeManager_GradientDirection.Value
		end

		-- Font settings (stored as string names)
		if Options.ThemeManager_FontName then
			theme.FontName = Options.ThemeManager_FontName.Value
		end
		if Options.ThemeManager_FontSize then
			theme.FontSize = Options.ThemeManager_FontSize.Value
		end

		writefile(self.Folder .. '/themes/' .. file .. '.json', httpService:JSONEncode(theme))
	end

	function ThemeManager:ReloadCustomThemes()
		local list = listfiles(self.Folder .. '/themes')

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == '.json' then
				-- i hate this but it has to be done ...

				local pos = file:find('.json', 1, true)
				local char = file:sub(pos, pos)

				while char ~= '/' and char ~= '\\' and char ~= '' do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == '/' or char == '\\' then
					table.insert(out, file:sub(pos + 1))
				end
			end
		end

		return out
	end

	function ThemeManager:SetLibrary(lib)
		self.Library = lib
	end

	function ThemeManager:BuildFolderTree()
		local paths = {}

		-- build the entire tree if a path is like some-hub/phantom-forces
		-- makefolder builds the entire tree on Synapse X but not other exploits

		local parts = self.Folder:split('/')
		for idx = 1, #parts do
			paths[#paths + 1] = table.concat(parts, '/', 1, idx)
		end

		table.insert(paths, self.Folder .. '/themes')
		table.insert(paths, self.Folder .. '/settings')

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function ThemeManager:SetFolder(folder)
		self.Folder = folder
		self:BuildFolderTree()
	end

	function ThemeManager:CreateGroupBox(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		return tab:AddLeftGroupbox('Themes')
	end

	function ThemeManager:ApplyToTab(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		local groupbox = self:CreateGroupBox(tab)
		self:CreateThemeManager(groupbox)
	end

	function ThemeManager:ApplyToGroupbox(groupbox)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		self:CreateThemeManager(groupbox)
	end


	function ThemeManager:StartMove()
		if self.MoveConnection then
			return
		end
		
		local RunService = game:GetService('RunService')
		local startTime = tick()
		local origC1 = self.Library.AccentColor1
		local origC2 = self.Library.AccentColor2
		
		self.MoveConnection = RunService.Heartbeat:Connect(function()
			local elapsed = (tick() - startTime) % 5
			local progress = elapsed / 5
			
			-- Shift hue between original colors
			local h1, s1, v1 = origC1:ToHSV()
			local h2, s2, v2 = origC2:ToHSV()
			
			local newH1 = (h1 + progress) % 1
			local newH2 = (h2 + progress) % 1
			
			self.Library.AccentColor1 = Color3.fromHSV(newH1, s1, v1)
			self.Library.AccentColor2 = Color3.fromHSV(newH2, s2, v2)
			
			local opt1 = Options.AccentColor1
			local opt2 = Options.AccentColor2
			if opt1 and opt1.SetValueRGB then pcall(opt1.SetValueRGB, opt1, self.Library.AccentColor1) end
			if opt2 and opt2.SetValueRGB then pcall(opt2.SetValueRGB, opt2, self.Library.AccentColor2) end
			
			self:ThemeUpdate()
		end)
	end

	function ThemeManager:StopMove()
		if self.MoveConnection then
			self.MoveConnection:Disconnect()
			self.MoveConnection = nil
		end
	end

	ThemeManager:BuildFolderTree()
end

return ThemeManager