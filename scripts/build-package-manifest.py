"""Generate explicit manifests and check the source inventory; performs no org writes."""
from pathlib import Path
from collections import Counter
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'force-app/main/default'
NS = 'http://soap.sforce.com/2006/04/metadata'
ET.register_namespace('', NS)

def tag(name):
    return '{' + NS + '}' + name

groups = {
    'ApexClass': [p.stem for p in (SOURCE / 'classes').glob('Scc*.cls')],
    'CustomObject': [p.name for p in (SOURCE / 'objects').iterdir() if p.is_dir() and p.name != 'Account'],
    'CustomField': [p.parent.parent.name + '.' + p.name.removesuffix('.field-meta.xml')
                    for p in (SOURCE / 'objects').glob('*/fields/*.field-meta.xml')],
    'ListView': [p.parent.parent.name + '.' + p.name.removesuffix('.listView-meta.xml')
                 for p in (SOURCE / 'objects').glob('*/listViews/*.listView-meta.xml')],
    'CustomMetadata': [p.name.removesuffix('.md-meta.xml') for p in (SOURCE / 'customMetadata').glob('*.md-meta.xml')],
    'LightningComponentBundle': ['sccCreditCodeAction'],
    'QuickAction': ['Account.Generate_Credit_Code'],
    'PermissionSet': ['Scc_Credit_Code_User', 'Scc_Credit_Code_Admin'],
    'CustomPermission': ['Scc_Generate_Credit_Code', 'Scc_Replace_Existing_Code'],
}
counts = Counter(name.split('.')[0] for name in groups['CustomMetadata'])
expected = {'SccRegionRule':369, 'SccIndustryRule':20, 'SccMilitaryRule':35,
            'SccCountryRule':4, 'SccOrganizationStatusRule':2, 'SccTerritoryRule':6}
assert dict(counts) == expected, counts
assert len(groups['ApexClass']) == 14
assert len(groups['CustomObject']) == 8
for path in SOURCE.rglob('*.xml'):
    ET.parse(path)

for filename, package_name in [('package.xml', None), ('unmanaged-code.xml', 'code')]:
    package = ET.Element(tag('Package'))
    if package_name:
        ET.SubElement(package, tag('fullName')).text = package_name
    for kind, members in groups.items():
        node = ET.SubElement(package, tag('types'))
        for member in sorted(members):
            ET.SubElement(node, tag('members')).text = member
        ET.SubElement(node, tag('name')).text = kind
    ET.SubElement(package, tag('version')).text = '67.0'
    ET.indent(package)
    path = ROOT / 'manifest' / filename
    path.parent.mkdir(exist_ok=True)
    ET.ElementTree(package).write(path, encoding='utf-8', xml_declaration=True)
print('Validated inventory:', dict(counts))
print('Explicit manifest members:', {kind:len(values) for kind,values in groups.items()})
