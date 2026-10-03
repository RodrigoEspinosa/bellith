-- Run: luajit scripts/tests/resolve-bridge-tests.lua
local bridge = dofile('Bellith/Resources/ResolveHarness/resolve_bridge.lua')
local realPrint = print
print = function() end
local timelines, current, serial = {}, nil, 0
local function item(name, start)
    return {
        GetMediaPoolItem=function() return nil end,
        GetName=function() return name end,
        GetStart=function() return start end,
        GetEnd=function() return start+24 end,
        GetSourceStartFrame=function() return 0 end,
        GetSourceEndFrame=function() return 23 end,
    }
end
local function timeline(name, items)
    serial=serial+1
    local id='t'..serial
    local t={items=items,markers={}}
    t.GetMarkers=function() return t.markers end
    t.AddMarker=function(_,frame,color,title,note,duration,customData)
        if t.markers[frame] then return false end
        t.markers[frame]={color=color,name=title,note=note,duration=duration,customData=customData}; return true
    end
    t.GetName=function() return name end
    t.GetUniqueId=function() return id end
    t.GetStartFrame=function() return 0 end
    t.GetEndFrame=function() return 48 end
    t.GetSetting=function() return '24' end
    t.GetTrackCount=function(_,kind) return kind=='audio' and 1 or 0 end
    t.GetItemListInTrack=function() return t.items end
    t.DuplicateTimeline=function(_,copyName)
        local copyItems={}; for i,v in ipairs(t.items) do copyItems[i]=v end
        local copy=timeline(copyName,copyItems)
        for frame,marker in pairs(t.markers) do copy.markers[frame]=marker end
        return copy
    end
    t.DeleteClips=function(_,remove,ripple)
        assert(ripple==false)
        local kept={}
        for _,v in ipairs(t.items) do
            local keep=true; for _,r in ipairs(remove) do if r==v then keep=false end end
            if keep then kept[#kept+1]=v end
        end
        t.items=kept; return true
    end
    timelines[#timelines+1]=t
    return t
end
local project={
    GetUniqueId=function() return 'project' end,
    GetName=function() return 'Fixture' end,
    GetCurrentTimeline=function() return current end,
    GetTimelineCount=function() return #timelines end,
    GetTimelineByIndex=function(_,i) return timelines[i] end,
    SetCurrentTimeline=function(_,t) current=t; return true end,
}
resolve={
    GetProjectManager=function() return {GetCurrentProject=function() return project end} end,
    GetProductName=function() return 'Mock Resolve' end,
    GetVersionString=function() return 'test' end,
}
local cases=0
local function check(value, message) assert(value,message); cases=cases+1 end
local function request(op, values)
    local r=values or {}; r.operation=op; r.requestID='test'; return bridge(r)
end
local source=timeline('Source',{item('Keep "quoted" café',0),item('Remove',24)})
source.items[1].GetClipEnabled=function() return false end
source.items[1].GetMediaPoolItem=function() return {GetUniqueId=function() return 'synthetic-media-id' end} end
current=source
local inspected=request('inspect')
check(inspected.ok and #inspected.snapshot.clips==2,'inspection')
local before=inspected.snapshot
check(before.clips[1].enabled==false and before.clips[2].enabled==nil,'false must remain distinct from unavailable enabled state')
check(before.clips[1].sourceStartFrame==0 and before.clips[1].sourceEndFrame==23,'typed source range preserves zero origin')
check(before.clips[1].mediaPoolItemID=='synthetic-media-id' and before.clips[2].mediaPoolItemID==nil,'source media identity remains unknown for items without media')
source.items[1].GetSourceStartFrame=function() return -1 end
local unknownRange=request('inspect').snapshot.clips[1]
check(unknownRange.sourceStartFrame==nil and unknownRange.sourceEndFrame==nil,'unavailable source range must not masquerade as zero')
source.items[1].GetSourceStartFrame=function() return 0 end
source.items[1].GetSourceStartFrame=function() error('Range unavailable for generated item') end
source.items[1].GetMediaPoolItem=function() error('No media pool item') end
local generated=request('inspect')
check(generated.ok and generated.snapshot.clips[1].sourceStartFrame==nil and generated.snapshot.clips[1].mediaPoolItemID==nil,
    'unavailable optional metadata must not stop timeline inspection')
source.items[1].GetSourceStartFrame=function() return math.huge end
check(request('inspect').snapshot.clips[1].sourceStartFrame==nil,'nonfinite source range stays unknown')
source.items[1].GetSourceStartFrame=function() return 0 end
source.items[1].GetMediaPoolItem=function() return {GetUniqueId=function() return 'synthetic-media-id' end} end
source.items[1].GetClipEnabled=function() return true end
check(request('inspect').snapshot.signature~=before.signature,'enabled state changes checkpoint signature')
source.items[1].GetClipEnabled=function() return false end
local common={projectID='project',timelineID=before.timelineID,expectedSignature=before.signature,copyName='Bellith - unit'}
local bad=request('duplicate',{projectID='wrong',timelineID=before.timelineID,expectedSignature=before.signature,copyName='Bellith - bad'})
check(not bad.ok and #timelines==1,'wrong project must not mutate')
bad=request('duplicate',{projectID='project',timelineID=before.timelineID,expectedSignature='stale',copyName='Bellith - bad'})
check(not bad.ok and #timelines==1,'stale snapshot must not mutate')
local copied=request('duplicate',common)
check(copied.ok and copied.snapshot.signature==before.signature and #timelines==2,'verified copy')
local copy=copied.snapshot
local keys={before.clips[2].key}
local function removal()
    return {projectID='project',timelineID=copy.timelineID,expectedSignature=copy.signature,copyName='Bellith - unit',sourceID=before.timelineID,sourceSignature=before.signature,removeKeys=keys}
end
local wrong=removal(); wrong.timelineID=before.timelineID
bad=request('removeClips',wrong)
check(not bad.ok and #current.items==2,'wrong active timeline must not mutate')
local original=removal(); original.sourceID=copy.timelineID
bad=request('removeClips',original)
check(not bad.ok and #current.items==2,'original must not be edited')
local missing=removal(); missing.removeKeys={'unknown'}
bad=request('removeClips',missing)
check(not bad.ok and #current.items==2,'unknown keys must not mutate')
local repeated=removal(); repeated.removeKeys={keys[1],keys[1]}
bad=request('removeClips',repeated)
check(not bad.ok and #current.items==2,'duplicate removals must not mutate')
local edited=request('removeClips',removal())
check(edited.ok and #edited.snapshot.clips==1 and #source.items==2,'copy removal preserves original')
bad=request('removeClips',removal())
check(not bad.ok and #current.items==1,'stale retry must not repeat edit')
current=source
local unchanged=request('inspect')
check(unchanged.snapshot.signature==before.signature,'original signature unchanged')
local markerCopy=request('duplicate',{projectID='project',timelineID=before.timelineID,expectedSignature=before.signature,copyName='Bellith - notes'})
check(markerCopy.ok,'note copy created')
local function markerRequest(markers)
    return {projectID='project',timelineID=markerCopy.snapshot.timelineID,expectedSignature=markerCopy.snapshot.signature,
        copyName='Bellith - notes',sourceID=before.timelineID,sourceSignature=before.signature,markers=markers}
end
bad=request('addMarkers',markerRequest({{frame=48,name='Outside',note=''}}))
check(not bad.ok and next(current.markers)==nil,'out of bounds notes must not mutate')
bad=request('addMarkers',markerRequest({{frame=5,name='A',note=''}, {frame=5,name='B',note=''}}))
check(not bad.ok and next(current.markers)==nil,'duplicate note offsets must not mutate')
local noted=request('addMarkers',markerRequest({{frame=5,name='Review "voice"',note='Listen locally, not an AI observation'}}))
check(noted.ok and #noted.snapshot.markers==1 and #current.items==2 and next(source.markers)==nil,'verified notes preserve clips and original')
check(noted.snapshot.markers[1].customData=='Bellith - notes:5','note ownership recorded')
bad=request('addMarkers',markerRequest({{frame=5,name='Retry',note=''}}))
check(not bad.ok and #request('inspect').snapshot.markers==1,'stale marker retry rejected')
local occupied=markerRequest({{frame=5,name='Overwrite',note=''}}); occupied.expectedSignature=noted.snapshot.signature
bad=request('addMarkers',occupied)
check(not bad.ok and current.markers[5].name=='Review "voice"','existing note cannot be overwritten')
print=realPrint
print('Resolve bridge: '..cases..' assertions passed')
