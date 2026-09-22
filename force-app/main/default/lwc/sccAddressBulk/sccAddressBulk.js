import { LightningElement } from 'lwc';
import preview from '@salesforce/apex/SccAddressBulkController.preview';
import submit from '@salesforce/apex/SccAddressBulkController.submit';
import progress from '@salesforce/apex/SccAddressBulkController.progress';
const labels = { READY:'可处理', PENDING:'排队中', RUNNING:'处理中', COMPLETED:'已补全', NO_MATCH:'未查到可靠结果', FAILED:'处理失败', SKIPPED:'已跳过', INVALID:'ID无效' };
export default class SccAddressBulk extends LightningElement {
    rows = []; csv = ''; busy = false; error = ''; submitted = false; timer;
    columns = [
        {label:'客户ID',fieldName:'inputId'}, {label:'客户名称',fieldName:'name'},
        {label:'状态',fieldName:'statusLabel'}, {label:'说明',fieldName:'detail',wrapText:true},
        {label:'省份',fieldName:'province'}, {label:'城市',fieldName:'city'},
        {label:'识别方式',fieldName:'methodLabel'}, {label:'来源',fieldName:'sourceText',wrapText:true}
    ];
    get submitDisabled() { return this.busy || this.submitted || !this.rows.some(r => r.status === 'READY'); }
    get refreshDisabled() { return this.busy || !this.submitted; }
    get summary() {
        const counts = {}; this.rows.forEach(r => { counts[r.statusLabel]=(counts[r.statusLabel] || 0)+1; });
        return Object.entries(counts).map(([name,count]) => `${name} ${count}`).join('；');
    }
    decorate(rows) {
        return rows.map((r,i) => {
            let sourceText = r.sources || '';
            try { sourceText = JSON.parse(sourceText).map(s => `${s.title || ''} ${s.url || ''}`).join('\n'); } catch(e) { /* Preserve raw audit text. */ }
            return {...r,key:String(i),statusLabel:labels[r.status] || r.status,sourceText,
                methodLabel:r.method === 'WEB' ? '联网查询' : r.method === 'STREET' ? '街道识别' : ''};
        });
    }
    async upload(event) {
        const file = event.target.files[0]; if (!file) return;
        clearTimeout(this.timer); this.rows=[]; this.csv=''; this.submitted=false; this.error='';
        if (file.size > 20000) { this.error='文件过大，请上传最多300条ID的单列CSV。'; return; }
        this.busy=true;
        try {
            this.csv=await new Promise((resolve,reject) => {
                const reader=new FileReader(); reader.onload=()=>resolve(reader.result); reader.onerror=()=>reject(new Error('无法读取文件')); reader.readAsText(file,'UTF-8');
            });
            this.rows=this.decorate(await preview({csv:this.csv}));
        } catch(e) { this.error=e.body?.message || e.message; }
        finally { this.busy=false; }
    }
    async start() {
        this.busy=true; this.error='';
        try { this.rows=this.decorate(await submit({csv:this.csv})); this.submitted=true; this.schedule(); }
        catch(e) { this.error=e.body?.message || e.message; }
        finally { this.busy=false; }
    }
    schedule() {
        clearTimeout(this.timer);
        if (this.rows.some(r => ['PENDING','RUNNING'].includes(r.status))) this.timer=setTimeout(()=>this.refresh(),10000);
    }
    async refresh() {
        clearTimeout(this.timer); if (this.busy) { this.schedule(); return; }
        this.busy=true; this.error='';
        try {
            const requestIds=this.rows.filter(r=>r.requestId).map(r=>r.requestId);
            const result=await progress({requestIds}); const updates=new Map(result.map(r=>[r.requestId,r]));
            this.rows=this.decorate(this.rows.map(r=>updates.has(r.requestId)?{...r,...updates.get(r.requestId)}:r));
            this.schedule();
        } catch(e) { this.error=e.body?.message || e.message; }
        finally { this.busy=false; }
    }
    disconnectedCallback() { clearTimeout(this.timer); }
}
