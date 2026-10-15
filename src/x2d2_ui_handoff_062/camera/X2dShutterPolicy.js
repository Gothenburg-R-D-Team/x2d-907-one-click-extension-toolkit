.pragma library
// One source: stock exposuresDone, exposed as exposures_in_session.
// No Started sound, reserved first frame, or timer-inferred completion.
function observe(previous,count,failed,enabled,electronic) {
    if(!Number.isInteger(count) || count<0)return {count:previous,frames:[]}
    if(!Number.isInteger(previous) || previous<0 || count<=previous)
        return {count:count,frames:[]}
    var frames=[]
    // Consume disabled/failed/mechanical counts; enabling never replays them.
    if(failed!==true && enabled===true && electronic===true)
        for(var frame=Math.max(previous+1,count-31);frame<=count;frame++)frames.push(frame)
    return {count:count,frames:frames}
}
