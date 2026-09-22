// Idempotent sandbox-only initialization. No historical customer scan.
Organization orgInfo = [SELECT IsSandbox FROM Organization LIMIT 1];
System.assert(orgInfo.IsSandbox, 'This script is authorized for sandbox only.');
Set<String> names = new Set<String>{'SccAddressSweep-0','SccAddressSweep-15','SccAddressSweep-30','SccAddressSweep-45'};
for (CronTrigger existing : [SELECT Id,CronJobDetail.Name FROM CronTrigger
    WHERE CronJobDetail.Name IN :names AND State IN ('WAITING','ACQUIRED','EXECUTING')]) names.remove(existing.CronJobDetail.Name);
for (Integer minute : new List<Integer>{0,15,30,45}) {
    String name = 'SccAddressSweep-' + minute;
    if (names.contains(name)) System.debug('ADDRESS_SWEEP=' + System.schedule(name, '0 '+minute+' * * * ?', new SccAddressSweep()));
}
