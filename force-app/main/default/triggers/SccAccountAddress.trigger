trigger SccAccountAddress on Account (after insert, after update) {
    SccAddressHandler.capture(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
