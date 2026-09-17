import { LightningElement, api } from 'lwc';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import loadAccount from '@salesforce/apex/SccActionController.loadAccount';
import research from '@salesforce/apex/SccActionController.research';
import generateFromResearch from '@salesforce/apex/SccActionController.generateFromResearch';
import saveManual from '@salesforce/apex/SccActionController.saveManual';
import preview from '@salesforce/apex/SccManualCodeService.preview';

export default class SccCreditCodeAction extends LightningElement {
    _recordId;
    account;
    researchResult;
    manualBody = '';
    manualPreview;
    replacementReason = '';
    busy = false;
    researching = false;

    @api
    set recordId(value) {
        this._recordId = value;
        if (value && !this.account && !this.busy) this.refreshAccount();
    }

    get recordId() {
        return this._recordId;
    }

    get hasCurrentCode() {
        return Boolean(this.account?.currentCode);
    }

    get sources() {
        return (this.researchResult?.sources || []).filter(value => /^https?:\/\//i.test(value?.url || '')).map((value, index) => ({
            ...value, name: value.name || value.url,
            domain: value.url.replace(/^https?:\/\//i, '').split('/')[0],
            key: `${index}-${value.url}`
        }));
    }

    get hasSources() { return this.sources.length > 0; }

    get autoFilledMessage() {
        const values = this.researchResult?.autoFilledFields || [];
        return values.length ? `已自动补充：${values.join('、')}` : '';
    }

    get conflictMessage() {
        return (this.researchResult?.warnings || []).join('\n');
    }

    get generationButtonLabel() {
        return this.researchResult?.officialCodeAccepted
            ? '采用已核验信用代码'
            : '按内部规则生成客户编码';
    }

    get codeDecisionClass() {
        return this.researchResult?.officialCodeAccepted
            ? 'slds-notify slds-notify_alert slds-alert_success'
            : 'slds-notify slds-notify_alert slds-alert_warning';
    }

    async refreshAccount() {
        this.busy = true;
        try {
            this.account = await loadAccount({ accountId: this.recordId });
        } catch (error) {
            this.toast('无法加载客户', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    handleManualBody(event) {
        this.manualBody = (event.detail.value || '').trim().toUpperCase();
        this.manualPreview = this.localPreview(this.manualBody);
    }

    localPreview(value) {
        if (!value || !/^[0-9A-Z]+$/.test(value) || (value.length !== 17 && value.length !== 18)) return null;
        const output = '0123456789ABCDEFGHJKLMNPQRTUWXY';
        const input = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        const body = value.substring(0, 17);
        let total = 0;
        let weight = 1;
        for (const character of body) {
            const digit = input.indexOf(character);
            if (digit < 0) return null;
            total = (total + ((digit * weight) % 31)) % 31;
            weight = (weight * 3) % 31;
        }
        const checkCharacter = output[(31 - total) % 31];
        const finalCode = `${body}${checkCharacter}`;
        if (value.length === 18 && value !== finalCode) return null;
        return { codeBody: body, checkCharacter, finalCode };
    }

    handleReason(event) {
        this.replacementReason = event.detail.value;
    }

    handleResearchValue(event) {
        this.researchResult = { ...this.researchResult, [event.target.dataset.field]: event.detail.value };
    }

    async handlePreview() {
        this.busy = true;
        this.manualPreview = null;
        const requestedBody = this.manualBody;
        try {
            const result = await preview({ codeBody: requestedBody });
            if (this.manualBody === requestedBody) this.manualPreview = result;
        } catch (error) {
            this.toast('无法计算校验码', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async handleManualSave() {
        this.busy = true;
        try {
            const finalCode = await saveManual({
                accountId: this.recordId,
                codeBody: this.manualBody,
                replacementReason: this.replacementReason
            });
            await this.finish(finalCode);
        } catch (error) {
            this.toast('保存失败', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async handleResearch() {
        this.busy = true;
        this.researching = true;
        this.researchResult = null;
        try {
            this.researchResult = await research({ accountId: this.recordId });
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            await this.refreshAccount();
        } catch (error) {
            this.toast('联网查询失败', this.message(error), 'error');
        } finally {
            this.researching = false;
            this.busy = false;
        }
    }

    async handleGenerate() {
        this.busy = true;
        try {
            const finalCode = await generateFromResearch({
                accountId: this.recordId,
                auditId: this.researchResult.auditId,
                selection: null,
                selectionJson: null,
                identityConfirmed: Boolean(this.researchResult.identityConfirmed),
                billingCountry: this.researchResult.billingCountry,
                billingState: this.researchResult.billingState,
                billingCity: this.researchResult.billingCity,
                industry: this.researchResult.industry,
                businessRegistrationNumber: this.researchResult.businessRegistrationNumber,
                isMilitary: Boolean(this.researchResult.isMilitary),
                militaryIndustryCode: this.researchResult.militaryIndustryCode,
                branchCode: this.researchResult.branchCode,
                replacementReason: this.replacementReason
            });
            const source = this.researchResult.officialCodeAccepted
                ? '来源：联网查询并核验通过'
                : '来源：内部编码规则生成';
            this.toast('客户编码已更新', `${finalCode}；${source}`, 'success');
            await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (error) {
            this.toast('生成失败', this.message(error), 'error');
        } finally {
            this.busy = false;
        }
    }

    async finish(finalCode) {
        await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        this.toast('客户编码已更新', finalCode, 'success');
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    message(error) {
        return error?.body?.message || error?.message || '未知错误';
    }
}
