-- Bellith's bounded Resolve adapter. Loaded through Resolve's built-in Lua Console.
-- No model-generated code is executed. Each request is a typed, validated operation.
local function quote(s)
    return '"' .. tostring(s):gsub('[%z\1-\31\\"]', function(c)
        local escapes = {['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
        return escapes[c] or string.format('\\u%04x', string.byte(c))
    end) .. '"'
end
local function json(v)
    if type(v) == 'string' then return quote(v) end
    if type(v) == 'number' then return tostring(v) end
    if type(v) == 'boolean' then return v and 'true' or 'false' end
    if type(v) ~= 'table' then return 'null' end
    local parts = {}
    if v.__array then
        for i = 1, #v do parts[#parts+1] = json(v[i]) end
        return '[' .. table.concat(parts, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do keys[#keys+1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do parts[#parts+1] = quote(k) .. ':' .. json(v[k]) end
    return '{' .. table.concat(parts, ',') .. '}'
end
local function optionalValue(object, method)
    local ok, value = pcall(function() return object[method](object) end)
    if ok then return value end
    return nil
end
local function optionalFrame(object, method)
    local value = optionalValue(object, method)
    if type(value)=='number' and value>=0 and value<math.huge and value==math.floor(value) then return value end
    return -1
end
local function inspect(project, timeline)
    assert(project, 'Open a Resolve project first.')
    assert(timeline, 'Open a timeline in Resolve first.')
    local clips, objects, keys = {__array=true}, {}, {__array=true}
    local tracks = {__array=true}
    local enabledByKey = {}
    for _, kind in ipairs({'video', 'audio', 'subtitle'}) do
        local count = timeline:GetTrackCount(kind) or 0
        tracks[#tracks+1] = count
        for track = 1, count do
            local items = timeline:GetItemListInTrack(kind, track) or {}
            for _, item in ipairs(items) do
                local media = optionalValue(item, 'GetMediaPoolItem')
                local mediaID = media and optionalValue(media, 'GetUniqueId') or nil
                if type(mediaID)~='string' or mediaID=='' then mediaID=nil end
                local name = item:GetName() or ''
                local start, finish = item:GetStart(), item:GetEnd()
                local sourceStart, sourceEnd = optionalFrame(item, 'GetSourceStartFrame'), optionalFrame(item, 'GetSourceEndFrame')
                local key = json({__array=true, kind, track, start, finish, sourceStart, sourceEnd, mediaID or '', name})
                local enabled
                local ok, value = pcall(function() return item:GetClipEnabled() end)
                if ok and type(value)=='boolean' then enabled=value; enabledByKey[key]=value end
                local clip = {key=key, name=name, kind=kind, track=track, startFrame=start, endFrame=finish, enabled=enabled, mediaPoolItemID=mediaID}
                if type(sourceStart)=='number' and type(sourceEnd)=='number' and sourceStart>=0 and sourceEnd>=sourceStart
                    and sourceStart==math.floor(sourceStart) and sourceEnd==math.floor(sourceEnd)
                    and sourceStart<math.huge and sourceEnd<math.huge then
                    clip.sourceStartFrame=sourceStart; clip.sourceEndFrame=sourceEnd
                end
                clips[#clips+1] = clip
                assert(#clips <= 500, 'This preview supports timelines with up to 500 items.')
                keys[#keys+1] = key
                if objects[key] ~= nil then objects[key] = false else objects[key] = item end
            end
        end
    end
    table.sort(keys)
    table.sort(clips, function(a,b) return a.key < b.key end)
    local markers = {__array=true}
    for frame, marker in pairs(timeline:GetMarkers() or {}) do
        markers[#markers+1] = {frame=frame, color=marker.color, name=marker.name or '', note=marker.note or '',
            duration=marker.duration, customData=marker.customData or ''}
    end
    table.sort(markers, function(a,b) return a.frame < b.frame end)
    local signature = json({keys=keys, tracks=tracks, start=timeline:GetStartFrame(), finish=timeline:GetEndFrame(), fps=tostring(timeline:GetSetting('timelineFrameRate')), markers=markers, enabledByKey=enabledByKey})
    return {
        projectID=project:GetUniqueId(), projectName=project:GetName(),
        timelineID=timeline:GetUniqueId(), timelineName=timeline:GetName(),
        startFrame=timeline:GetStartFrame(), endFrame=timeline:GetEndFrame(),
        frameRate=tostring(timeline:GetSetting('timelineFrameRate')),
        product=resolve:GetProductName(), version=resolve:GetVersionString(),
        clips=clips, signature=signature, markers=markers, trackCounts=tracks
    }, objects
end
local function findTimeline(project, id)
    for i = 1, project:GetTimelineCount() do
        local t = project:GetTimelineByIndex(i)
        if t:GetUniqueId() == id then return t end
    end
    error('The recorded timeline is no longer in this project.')
end
return function(request)
    local ok, result = pcall(function()
        assert(type(request.requestID) == 'string', 'Invalid request envelope.')
        local project = resolve:GetProjectManager():GetCurrentProject()
        assert(project, 'Open a Resolve project first.')
        local current = project:GetCurrentTimeline()
        if request.operation == 'inspect' then
            if request.sourceID then
                assert(project:GetUniqueId() == request.projectID, 'Project changed. Select the session project.')
                assert(inspect(project, findTimeline(project, request.sourceID)).signature == request.sourceSignature, 'Original timeline changed. Start a new session to replan.')
            end
            return {snapshot=inspect(project, current), sourceUnchanged=true}
        end
        assert(project:GetUniqueId() == request.projectID, 'Project changed. Inspect again before continuing.')
        assert(current and current:GetUniqueId() == request.timelineID, 'Active timeline changed. Select the recorded timeline before continuing.')
        local before = inspect(project, current)
        assert(before.signature == request.expectedSignature, 'Timeline content changed since inspection. No action was applied.')
        if request.operation == 'duplicate' then
            assert(type(request.copyName) == 'string' and request.copyName:match('^Bellith %- '), 'Invalid working copy name.')
            for i = 1, project:GetTimelineCount() do
                assert(project:GetTimelineByIndex(i):GetName() ~= request.copyName, 'Working copy already exists. Inspect it to recover; do not duplicate again.')
            end
            local copy = current:DuplicateTimeline(request.copyName)
            assert(copy, 'Resolve did not create the working copy.')
            assert(copy:GetUniqueId() ~= current:GetUniqueId(), 'Resolve returned the original timeline.')
            assert(project:SetCurrentTimeline(copy), 'Working copy exists, but Resolve could not select it. Select it manually and inspect.')
            local after = inspect(project, copy)
            assert(after.signature == before.signature, 'Working copy differs from the source. Review it manually.')
            assert(inspect(project, current).signature == before.signature, 'Source changed while creating the copy.')
            return {snapshot=after, sourceUnchanged=true}
        end
        assert(request.operation == 'removeClips' or request.operation == 'addMarkers', 'Unsupported operation.')
        assert(request.sourceID ~= request.timelineID, 'Edits to the original timeline are not allowed.')
        assert(current:GetName() == request.copyName, 'Working copy name changed. Review before continuing.')
        local source = findTimeline(project, request.sourceID)
        assert(inspect(project, source).signature == request.sourceSignature, 'Original timeline changed. Pausing before any further edits.')
        local snapshot, objects = inspect(project, current)
        if request.operation == 'addMarkers' then
            assert(type(request.markers) == 'table' and #request.markers > 0 and #request.markers <= 20, 'Choose between 1 and 20 timeline notes.')
            local occupied, expected = {}, {__array=true}
            for _, marker in ipairs(snapshot.markers) do occupied[marker.frame]=true; expected[#expected+1]=marker end
            for _, marker in ipairs(request.markers) do
                assert(type(marker.frame)=='number' and marker.frame==math.floor(marker.frame) and marker.frame>=0
                    and marker.frame < snapshot.endFrame-snapshot.startFrame and not occupied[marker.frame], 'Marker offset is invalid, repeated, or already occupied.')
                assert(type(marker.name)=='string' and marker.name:match('%S') and #marker.name<=480
                    and type(marker.note)=='string' and #marker.note<=8000, 'Invalid marker text.')
                occupied[marker.frame]=true
                expected[#expected+1]={frame=marker.frame, color='Blue', name=marker.name, note=marker.note,
                    duration=1, customData=request.copyName..':'..string.format('%.0f', marker.frame)}
            end
            table.sort(expected,function(a,b) return a.frame<b.frame end)
            for _, marker in ipairs(request.markers) do
                assert(project:GetCurrentTimeline():GetUniqueId()==request.timelineID, 'Active timeline changed.')
                assert(current:AddMarker(marker.frame,'Blue',marker.name,marker.note,1,
                    request.copyName..':'..string.format('%.0f',marker.frame)), 'Resolve did not confirm a note. Inspect the copy; do not retry blindly.')
            end
            local after=inspect(project,current)
            assert(json(after.markers)==json(expected), 'Marker result differs from the reviewed notes. Inspect before continuing.')
            assert(json(after.clips)==json(snapshot.clips) and json(after.trackCounts)==json(snapshot.trackCounts) and after.frameRate==snapshot.frameRate
                and after.startFrame==snapshot.startFrame and after.endFrame==snapshot.endFrame,
                'Clip layout changed while adding notes. Review the working copy.')
            assert(inspect(project,source).signature==request.sourceSignature,'Original timeline changed during the operation.')
            return {snapshot=after,sourceUnchanged=true}
        end
        local selected, seen = {}, {}
        assert(type(request.removeKeys) == 'table' and #request.removeKeys > 0 and #request.removeKeys <= 50, 'Choose between 1 and 50 whole clips.')
        for _, key in ipairs(request.removeKeys) do
            assert(type(key) == 'string' and not seen[key] and objects[key], 'A requested clip is missing, repeated, or ambiguous.')
            seen[key] = true
            selected[#selected+1] = objects[key]
        end
        assert(project:GetCurrentTimeline():GetUniqueId() == request.timelineID, 'Active timeline changed.')
        assert(current:DeleteClips(selected, false), 'Resolve did not confirm the removal. Inspect the working copy; do not retry blindly.')
        local after = inspect(project, current)
        assert(json(after.markers)==json(snapshot.markers), 'Existing markers changed during removal. Review the working copy.')
        local expected = {}
        for _, clip in ipairs(snapshot.clips) do if not seen[clip.key] then expected[clip.key] = (expected[clip.key] or 0) + 1 end end
        for _, clip in ipairs(after.clips) do
            assert(expected[clip.key] and expected[clip.key] > 0, 'Unexpected clip layout after removal. Review the working copy manually.')
            expected[clip.key] = expected[clip.key] - 1
        end
        for _, count in pairs(expected) do assert(count == 0, 'More clips changed than requested. Review the working copy manually.') end
        assert(inspect(project, source).signature == request.sourceSignature, 'Original timeline changed during the operation.')
        return {snapshot=after, sourceUnchanged=true}
    end)
    local envelope = {requestID=request.requestID, ok=ok}
    if ok then envelope.snapshot=result.snapshot; envelope.sourceUnchanged=result.sourceUnchanged
    else envelope.error=tostring(result) end
    print('BELLITH_RESULT:' .. json(envelope))
    return envelope
end
