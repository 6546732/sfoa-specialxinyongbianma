/** Resume durable requests whose saving transaction had no queueable slot available. */
public without sharing class SccAddressSweep implements Schedulable {
    public void execute(SchedulableContext context) { SccAddressJob.sweep(); }
}
