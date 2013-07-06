require "./bencode"
require "test/unit"
 
class TestBencode < Test::Unit::TestCase
 
  def test_integers
    assert_equal(32, Bencode.from_string('i32e').decode )
    assert_equal(0, Bencode.from_string('i0e').decode )
    assert_equal(-5, Bencode.from_string('i-5e').decode )
  end

  def test_strings
    assert_equal('1231', Bencode.from_string('4:1231').decode )
    assert_equal('', Bencode.from_string('0:').decode )
    assert_equal('zxcvbnmhjk', Bencode.from_string('10:zxcvbnmhjk').decode )
  end

  def test_lists
    assert_equal([], Bencode.from_string('le').decode )
    assert_equal([1, 2, 3], Bencode.from_string('li1ei2ei3ee').decode )
    assert_equal(['list', [1,2,3]], Bencode.from_string('l4:listli1ei2ei3eee').decode )
  end

  def test_dictionaries
    assert_equal({}, Bencode.from_string('de').decode )
    assert_equal({test: 'result'}, Bencode.from_string('d4:test6:resulte').decode )
    assert_equal({test: 'result', dict: {tset: 'tluser'} }, Bencode.from_string('d4:test6:result4:dictd4:tset6:tluseree').decode )
  end

  def test_whole
    data = 'd4:testl15:abcdeabcdeabcdeli123ei321e2:zxee5:test2l3:poii-43ed2:fgi0eeee'
    result = {test: ['abcdeabcdeabcde', [123, 321, 'zx']], test2: ['poi', -43, {fg: 0}]}
    assert_equal(result, Bencode.from_string(data).decode )
  end
end
