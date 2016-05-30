if controllerComboHandler==nil then controllerComboHandler = {} end

function controllerComboHandler.parseComboPart(segment)
  local value = 0

  if segment:match('DU') then value = (value | 1); segment=segment:gsub('DU', '') end
  if segment:match('DD') then value = (value | 2); segment=segment:gsub('DD', '') end
  if segment:match('DL') then value = (value | 4); segment=segment:gsub('DL', '') end
  if segment:match('DR') then value = (value | 8); segment=segment:gsub('DR', '') end -- sum is 0xF

  if segment:match('LA') then value = (value | 0x0040); segment=segment:gsub('LA', '') end
  if segment:match('RA') then value = (value | 0x0080); segment=segment:gsub('RA', '') end
  if segment:match('LB') then value = (value | 0x0100); segment=segment:gsub('LB', '') end
  if segment:match('RB') then value = (value | 0x0200); segment=segment:gsub('RB', '') end  -- sum is 0x3C0

  if segment:match('A') then value = (value | 0x1000) end
  if segment:match('B') then value = (value | 0x2000) end
  if segment:match('X') then value = (value | 0x4000) end
  if segment:match('Y') then value = (value | 0x8000) end -- sum is 0xF000
                                                          -- sum of all needed buttons is 0xF3CF

  if (value &  3)== 3 then value=-1 end -- up and down can't be pressed at the same time
  if (value & 12)==12 then value=-1 end -- also left and right

  return value
end










function controllerComboHandler.collidesWithExistingCombo(newCombo)

  local function oneComboIsInsideAnotherCombo(searchCombo,insideThisCombo)
    if #searchCombo>#insideThisCombo then return false end
    for shifted=0,(#insideThisCombo-#searchCombo) do
      local found=true
      for i=1,#searchCombo-1 do
        if insideThisCombo[i+shifted] ~= searchCombo[i] then found=false; break end
      end
      if found then return true end
    end
    return false
  end

  local function mergeCombos(t1,t2)
    local tmp={}
    for i=1,#t1 do tmp[1+#tmp]=t1[i] end
    for i=2,#t2 do tmp[1+#tmp]=t2[i] end
    return tmp
  end

  local newCombo_x2 = mergeCombos(newCombo,newCombo)

  -- detect simple collisions
  for _,combo in ipairs(controllerComboHandler.registeredCombos) do
    if oneComboIsInsideAnotherCombo(newCombo,combo) or oneComboIsInsideAnotherCombo(combo,newCombo) then
      showMessage(string.format('collision between "%s"(added) and "%s"', newCombo.comboName, combo.comboName))
      return true
    end
    if oneComboIsInsideAnotherCombo(combo,newCombo_x2) then
      showMessage(string.format('collision: using "%s" two times in row will activate "%s" too', newCombo.comboName, combo.comboName))
      return true
    end
  end

  -- detect other kind of collisions (combo1+combo2 can trigger combo3)
  -- I think I don't have to check combo1+combo2+combo3 and more
  for _,c1 in ipairs(controllerComboHandler.registeredCombos) do
    for _,c2 in ipairs(controllerComboHandler.registeredCombos) do
      if oneComboIsInsideAnotherCombo(newCombo,mergeCombos(c1,c2)) then
        showMessage(string.format('collision: "%s"(added) will be activated with "%s" followed by "%s"',
                                  newCombo.comboName,c1.comboName,c2.comboName))
        return true
      end
      if c1.ID~=c2.ID and oneComboIsInsideAnotherCombo(c2,mergeCombos(c1,newCombo)) then
        showMessage(string.format('collision: "%s" will be activated with "%s" followed by "%s"(added)',
                                  c2.comboName,c1.comboName,newCombo.comboName))
        return true
      end
      if c1.ID~=c2.ID and oneComboIsInsideAnotherCombo(c2,mergeCombos(newCombo,c1)) then
        showMessage(string.format('collision: "%s" will be activated with "%s"(added) followed by "%s"',
                                  c2.comboName,newCombo.comboName,c1.comboName))
        return true
      end
    end
  end

  return false
end














function controllerComboHandler.addNewCombo(comboName,functionToCall, ...)
  local newComboTable={}
  newComboTable.comboName=comboName
  newComboTable.functionToCall=functionToCall
  newComboTable.position=1

  local newComboString=''

  -- parse begin
  for i,v in ipairs{...} do
    newComboString=newComboString..(v..',')
  end
  newComboString = newComboString:gsub('[ {}]',''):upper() -- remove spaces and '{' and '}', and change to UPPER case

  local withRelease=true
  if newComboString:match('NORELEASE') then withRelease=false; newComboString=newComboString:gsub('NORELEASE', '') end

  newComboTable[1+#newComboTable]=0
  for newComboSegment in newComboString:gmatch("([^,]+)") do
    local value=controllerComboHandler.parseComboPart(newComboSegment)

    if value==-1 then
      showMessage(string.format([["%s" has wrong combo - e.g. digital pad left and right can't be pressed at the same time]], newComboTable.comboName))
      return false
    end
    newComboTable[1+#newComboTable]=value
    if withRelease then newComboTable[1+#newComboTable]=0 end
  end
  if newComboTable[#newComboTable]~=0 then newComboTable[1+#newComboTable]=0 end
  -- parse end

  local collision = controllerComboHandler.collidesWithExistingCombo(newComboTable)
  if collision then return false end

  newComboTable.ID=#controllerComboHandler.registeredCombos

  table.insert(controllerComboHandler.registeredCombos, newComboTable)
  return true
end








function controllerComboHandler.ThreadFunc(thread)
 thread.Name = 'controllerComboHandler.ThreadFunc'
 thread.freeOnTerminate(false)

  local function expectedButtons(comboPart,btns)
    if btns==0 then print('note to developer: func expectedButtons got btns=0') end
    return ((btns | comboPart) == comboPart)
  end

  local function maybeStartedFromTheScratch(combo,btns)
    if btns==0 then print('note to developer: func maybeStartedFromTheScratch got btns=0') end

    combo.position=1 -- reset by default
    if combo[2]==btns then combo.position=3
    elseif expectedButtons(combo[2],btns) then combo.position=2 end
  end

 while not thread.Terminated do
  local state    = getXBox360ControllerState()
  local wButtons = state and (state.wButtons & 0xF3CF)

  if state~=nil and controllerComboHandler.wButtonsOld~=wButtons
  then
   controllerComboHandler.wButtonsOld = wButtons

   for _,combo in ipairs(controllerComboHandler.registeredCombos) do

    if combo[combo.position]==0 then -- expecting all buttons to be released

     if wButtons==0 then -- if all released
       if combo.position==#combo then -- then if whole combo,
         synchronize(combo.functionToCall) -- call function
         combo.position=2 -- and reset (pos=2 because buttons already released)
       else
         combo.position=combo.position+1 -- else go to the next part of combo
       end

     --still pressed
     elseif (combo.position>1) and not expectedButtons(combo[combo.position-1],wButtons) then
       --not expected button(s) for previous part of combo
       maybeStartedFromTheScratch(combo,wButtons)-- but, maybe someone started combo from the scratch
     end

    else -- expecting at least one button pressed

     if wButtons==0 then -- if no pressed button then reset
      combo.position=2   -- (pos=2 because buttons already released)

     elseif not expectedButtons(combo[combo.position],wButtons) then
      -- not expected button(s) for current part of combo
      maybeStartedFromTheScratch(combo,wButtons)-- but, maybe someone started combo from the scratch

     elseif wButtons==combo[combo.position] then -- those buttons we wanted, nothing less, nothing more
       combo.position=combo.position+1 -- go to the next part of combo
     end
    end

    synchronize(debugCombosGui) -- debug with gui
   end -- for _,combo in ipairs

  end
 end
end






function controllerComboHandler.startListening()
  controllerComboHandler.stopListening()
  controllerComboHandler.Thread=createNativeThread(controllerComboHandler.ThreadFunc)
end

function controllerComboHandler.stopListening()
  if controllerComboHandler.Thread then -- kill previous thread
     controllerComboHandler.Thread.terminate()
     controllerComboHandler.Thread.waitfor()
     controllerComboHandler.Thread.destroy()
     controllerComboHandler.Thread=nil
     controllerComboHandler.wButtonsOld=-1
  end
end

controllerComboHandler.registeredCombos={}

controllerComboHandler.addNewCombo('cheat5',function () print('cheat1') end,"A,Y,X,B")
controllerComboHandler.addNewCombo('cheat6',function () print('cheat2') end,"DD,DU,DL,DR")

controllerComboHandler.startListening()
