import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xjtu_campus/core/crypto/rsa_pkcs1.dart';
import 'package:xjtu_campus/features/schedule/data/jwxt_course_mapper.dart';
import 'package:xjtu_campus/features/schedule/data/workflow_kebiao_mapper.dart';

void main() {
  test('RSA 加密结果带学校要求的 __RSA__ 前缀', () {
    const pem = '''
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDitxewhO/Z30ZjdfpBepy6uEYW
ZB/S8U36gX/tDMvWFr7V3jY+3NaM6IjktAlfBXlDbEQnwP8Bd3YT4zuT7oIeUhl6
Y4mFIvqIRcyi1ahzthUrxFHTnc7ej+JvA3njwwzLiOMbT6ShQPgAYQmxrqzKWwxp
fKnao11O/4niMaWQ3QIDAQAB
-----END PUBLIC KEY-----
''';
    final cipher = rsaEncryptPassword('not-a-real-password', pem);
    expect(cipher.startsWith('__RSA__'), isTrue);
    expect(cipher.length, greaterThan(20));
    expect(cipher.contains('not-a-real-password'), isFalse);
  });

  test('JwxtCourseMapper 解析教务课表行', () {
    final courses = JwxtCourseMapper.fromRows([
      {
        'WID': 'c1',
        'KCM': '线性代数',
        'SKJS': '赵老师',
        'JASMC': '主楼A-203',
        'XXXQMC': '兴庆校区',
        'SKXQ': 3,
        'KSJC': 3,
        'JSJC': 4,
        'SKZC': '101010',
        'XNXQDM': '2026-2027-1',
      },
    ]);
    expect(courses, hasLength(1));
    final course = courses.single;
    expect(course.name, '线性代数');
    expect(course.teacher, '赵老师');
    expect(course.weekday, 3);
    expect(course.startPeriod, 3);
    expect(course.endPeriod, 4);
    expect(course.weeks, [1, 3, 5]);
    expect(course.building, '主楼A');
    expect(course.campus, '兴庆校区');
  });

  test('WorkflowKebiaoMapper 解析 docs/workflow-kebiao-sample.json', () {
    final file = File('docs/workflow-kebiao-sample.json');
    expect(file.existsSync(), isTrue);
    final root = jsonDecode(file.readAsStringSync());
    final courses = WorkflowKebiaoMapper.fromJson(root);
    expect(courses, hasLength(3));
    expect(courses.first.name, '工程与社会');
    expect(courses.first.teacher, '樊超');
    expect(courses.first.room, '西2西-407');
    expect(courses.first.building, '西2西');
    expect(courses.first.weekday, 2);
    expect(courses.first.startPeriod, 1);
    expect(courses.first.endPeriod, 2);
    expect(courses.first.weeks, [1]);
    expect(WorkflowKebiaoMapper.termOf(root), '2026-2027-1');
  });
}
