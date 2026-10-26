-- Tests for mathutil. Run headless with `rive <dir> --test`, or live: the
-- rive re-runs these on every save and streams results to the log.
local mathutil = require('mathutil')

function setup(test: Tester)
    test.group('add', function()
        test.case('sums positives', function(expect)
            expect(mathutil.add(2, 3)).is(5)
            expect(mathutil.add(2, 3)).greaterThanOrEqual(5)
        end)
        test.case('sums negatives', function(expect)
            expect(mathutil.add(-2, -3)).is(-5)
        end)
    end)

    test.group('clamp', function()
        test.case('clamps high', function(expect)
            expect(mathutil.clamp(10, 0, 5)).is(5)
        end)
        test.case('clamps low', function(expect)
            expect(mathutil.clamp(-1, 0, 5)).is(0)
        end)
        test.case('leaves in-range values', function(expect)
            expect(mathutil.clamp(3, 0, 5)).is(3)
            expect(mathutil.clamp(3, 0, 5)).lessThan(5)
        end)
        test.case('intentional failure', function(expect)
            -- Fails on purpose to exercise failure reporting and exit codes.
            expect(mathutil.clamp(10, 0, 5)).is(10)
        end)
    end)

    test.group('errors', function()
        -- Passes only when the body raises an error holding the message.
        test.errors('rejects a missing operand', function(expect)
            mathutil.add(nil :: any, 1)
        end, 'attempt to perform arithmetic')
    end)
end

return function(): Tests
    return setup
end
